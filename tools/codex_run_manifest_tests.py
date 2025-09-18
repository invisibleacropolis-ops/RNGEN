"""CLI helper for running the Godot manifest driven test suite under Codex.

This module provides a small command line interface that shells out to Godot
via :class:`tools.codex_godot_process_manager.CodexGodotProcessManager`.  It is
designed to mirror the automation hooks used by Codex operators so that local
developers can easily reproduce and debug failing manifest suites.

The entry point performs the following high level workflow:

* Reset any stale ``tests/results.*`` artifacts to avoid confusing Codex with
  old reports.
* Launch a headless Godot instance with ``run_all_tests.gd`` which emits JSON
  and JUnit style reports that the script parses after the engine exits.
* Summarise the run for humans while simultaneously producing a structured JSON
  payload tailored for Codex' streaming diagnostics channel.
* Optionally persist those outputs to disk when ``--output`` is supplied so the
  Codex orchestrator can snapshot the run.

Outside engineers can use this entry point directly or embed it inside larger
automation flows – the defaults pull from the ``CODEX_GODOT_BIN`` and
``CODEX_PROJECT_ROOT`` environment variables so that minimal configuration is
required once those are exported.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import textwrap
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence
from xml.etree import ElementTree

# ---------------------------------------------------------------------------
# Ensure the repository root is importable when the module is executed as a
# script via ``python tools/codex_run_manifest_tests.py``.
#
# Python initialises ``sys.path[0]`` with the directory containing the script
# being executed.  When this file is launched directly that directory is the
# ``tools`` folder itself, which means attempts to import ``tools.*`` resolve to
# ``<tools>/tools`` instead of the repository root.  By appending the parent of
# this file we make the top level package discoverable without affecting module
# executions (where ``__package__`` is populated by the interpreter).
if __package__ is None:  # pragma: no cover - import side effect
    sys.path.append(str(Path(__file__).resolve().parent.parent))

from tools.codex_godot_process_manager import CodexGodotProcessManager


# ---------------------------------------------------------------------------
# Result model


@dataclass
class ScriptReport:
    """Represents the outcome of a single GDScript test file."""

    path: str
    passed: bool
    total: int
    successes: int
    failures: int
    errors: List[str] = field(default_factory=list)
    xml_failure: Optional[str] = None

    @property
    def status(self) -> str:
        return "PASS" if self.passed else "FAIL"


@dataclass
class ManifestSummary:
    """Aggregated statistics produced by ``run_all_tests.gd``."""

    scripts_passed: int = 0
    scripts_failed: int = 0
    assertions: int = 0
    error: Optional[str] = None

    @property
    def total_scripts(self) -> int:
        return self.scripts_passed + self.scripts_failed


@dataclass
class ManifestRun:
    """Structured payload shared with Codex and printed for humans."""

    exit_code: int
    summary: ManifestSummary
    scripts: List[ScriptReport]
    manifest_path: str
    results_json: Optional[str]
    results_xml: Optional[str]
    duration: float
    logs: List[Dict[str, str]] = field(default_factory=list)
    attempt: int = 1
    max_attempts: int = 1

    def as_json(self) -> Dict[str, object]:
        """Serialize the payload for Codex friendly consumption."""

        return {
            "exit_code": self.exit_code,
            "summary": {
                "scripts_passed": self.summary.scripts_passed,
                "scripts_failed": self.summary.scripts_failed,
                "assertions": self.summary.assertions,
                "error": self.summary.error,
            },
            "manifest_path": self.manifest_path,
            "results": {
                "json": self.results_json,
                "xml": self.results_xml,
            },
            "attempt": self.attempt,
            "max_attempts": self.max_attempts,
            "duration_seconds": self.duration,
            "logs": self.logs,
            "scripts": [
                {
                    "path": script.path,
                    "status": script.status,
                    "passed": script.passed,
                    "total": script.total,
                    "successes": script.successes,
                    "failures": script.failures,
                    "errors": script.errors,
                    "xml_failure": script.xml_failure,
                }
                for script in self.scripts
            ],
        }

    def human_summary(self) -> str:
        """Render a concise human friendly summary of the run."""

        lines = [
            "Godot manifest test run complete:",
            f"  Exit code: {self.exit_code}",
            f"  Scripts passed: {self.summary.scripts_passed}",
            f"  Scripts failed: {self.summary.scripts_failed}",
            f"  Total assertions: {self.summary.assertions}",
        ]
        if self.summary.error:
            lines.append(f"  Error: {self.summary.error}")

        if self.scripts:
            lines.append("")
            lines.append("Script outcomes:")
            for script in self.scripts:
                detail = f"{script.status}: {script.path} ({script.successes}/{script.total})"
                lines.append(f"  - {detail}")
                if script.errors:
                    for entry in script.errors:
                        wrapped = textwrap.fill(entry, subsequent_indent="      ")
                        lines.append(f"      error: {wrapped}")
                if script.xml_failure and script.xml_failure not in script.errors:
                    wrapped = textwrap.fill(
                        script.xml_failure,
                        subsequent_indent="      ",
                    )
                    lines.append(f"      junit: {wrapped}")

        if self.logs:
            lines.append("")
            lines.append("Recent diagnostics:")
            excerpt = self.logs[-5:]
            for log in excerpt:
                timestamp = time.strftime(
                    "%H:%M:%S",
                    time.localtime(float(log.get("timestamp", time.time()))),
                )
                source = log.get("stream", "stderr")
                text = log.get("text", "")
                lines.append(f"  [{timestamp}] {source}: {text}")

        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Utility helpers


def _parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the Godot manifest tests using the Codex orchestration helpers.",
    )
    parser.add_argument(
        "--project-root",
        default=os.environ.get("CODEX_PROJECT_ROOT"),
        help="Filesystem path to the Godot project (defaults to CODEX_PROJECT_ROOT).",
    )
    parser.add_argument(
        "--godot-binary",
        default=os.environ.get("CODEX_GODOT_BIN"),
        help="Path to the Godot executable (defaults to CODEX_GODOT_BIN).",
    )
    parser.add_argument(
        "--manifest",
        default="tests/tests_manifest.json",
        help="Path to the manifest consumed by run_all_tests.gd.",
    )
    parser.add_argument(
        "--results-json",
        default="tests/results.json",
        help="Location of the JSON report produced by Godot.",
    )
    parser.add_argument(
        "--results-xml",
        default="tests/results.xml",
        help="Location of the optional JUnit XML report produced by Godot.",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=1,
        help="Number of attempts to make if the run fails (defaults to 1).",
    )
    parser.add_argument(
        "--retry-delay",
        type=float,
        default=0.0,
        help="Seconds to wait between retries when --max-retries > 1.",
    )
    parser.add_argument(
        "--output",
        metavar="DIR",
        help="Directory where summary.txt and codex_payload.json snapshots should be stored.",
    )
    parser.add_argument(
        "--keep-artifacts",
        action="store_true",
        help="Skip the automatic deletion of pre-existing test reports.",
    )
    return parser.parse_args(argv)


def _cleanup_reports(paths: Iterable[Path]) -> None:
    for path in paths:
        try:
            path.unlink()
        except FileNotFoundError:
            continue


def _collect_diagnostics(manager: CodexGodotProcessManager, sink: List[Dict[str, str]]) -> None:
    for payload in manager.iter_stderr_diagnostics():
        if isinstance(payload, dict):
            sink.append({
                "timestamp": str(payload.get("timestamp", time.time())),
                "stream": str(payload.get("stream", "stderr")),
                "text": str(payload.get("text", "")),
                "level": str(payload.get("level", "error")),
            })


def _run_godot(
    *,
    project_root: Path,
    godot_binary: Path,
    extra_env: Optional[Dict[str, str]] = None,
) -> tuple[int, List[Dict[str, str]], float]:
    """Launch Godot using the process manager and wait for completion."""

    manager = CodexGodotProcessManager(
        godot_binary=str(godot_binary),
        project_root=str(project_root),
        extra_args=["--script", "res://tests/run_all_tests.gd", "--quit"],
        env_overrides=extra_env,
    )

    logs: List[Dict[str, str]] = []
    start_time = time.perf_counter()

    with manager:
        stderr_thread = threading.Thread(
            target=_collect_diagnostics,
            args=(manager, logs),
            name="CodexGodotDiagnosticsCollector",
            daemon=True,
        )
        stderr_thread.start()

        assert manager._process is not None  # Access internal state for wait semantics.
        exit_code = manager._process.wait()
        manager.stop()
        stderr_thread.join(timeout=1.0)

    duration = time.perf_counter() - start_time
    return exit_code, logs, duration


def _load_json_results(path: Path) -> tuple[ManifestSummary, List[ScriptReport]]:
    if not path.exists():
        return ManifestSummary(error=f"JSON results missing at {path}"), []

    data = json.loads(path.read_text(encoding="utf-8"))
    summary_data = data.get("summary", {}) if isinstance(data, dict) else {}
    tests_data = data.get("tests", []) if isinstance(data, dict) else []

    summary = ManifestSummary(
        scripts_passed=int(summary_data.get("scripts_passed", 0) or 0),
        scripts_failed=int(summary_data.get("scripts_failed", 0) or 0),
        assertions=int(summary_data.get("assertions", 0) or 0),
        error=summary_data.get("error"),
    )

    scripts: List[ScriptReport] = []
    if isinstance(tests_data, list):
        for entry in tests_data:
            if not isinstance(entry, dict):
                continue
            scripts.append(
                ScriptReport(
                    path=str(entry.get("path", "")),
                    passed=bool(entry.get("passed", False)),
                    total=int(entry.get("total", 0) or 0),
                    successes=int(entry.get("successes", 0) or 0),
                    failures=int(entry.get("failures", 0) or 0),
                    errors=[str(err) for err in entry.get("errors", []) if isinstance(err, str)],
                )
            )

    return summary, scripts


def _augment_with_xml(path: Path, scripts: List[ScriptReport]) -> None:
    if not path.exists():
        return

    try:
        xml_root = ElementTree.fromstring(path.read_text(encoding="utf-8"))
    except ElementTree.ParseError:
        return

    failures: Dict[str, str] = {}
    for testcase in xml_root.findall(".//testcase"):
        name = testcase.get("name")
        if not name:
            continue
        failure_node = testcase.find("failure")
        if failure_node is not None:
            text = failure_node.get("message") or failure_node.text or ""
            failures[name] = text.strip()

    if not failures:
        return

    for script in scripts:
        failure_text = failures.get(script.path)
        if failure_text:
            script.xml_failure = failure_text
            if failure_text not in script.errors:
                script.errors.append(failure_text)


def _persist_outputs(output_dir: Path, run: ManifestRun) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    summary_path = output_dir / "summary.txt"
    summary_path.write_text(run.human_summary() + "\n", encoding="utf-8")
    payload_path = output_dir / "codex_payload.json"
    payload_path.write_text(json.dumps(run.as_json(), indent=2) + "\n", encoding="utf-8")


def _execute_attempt(
    *,
    attempt: int,
    max_attempts: int,
    project_root: Path,
    godot_binary: Path,
    manifest_path: Path,
    json_path: Path,
    xml_path: Path,
    cleanup: bool,
) -> ManifestRun:
    if cleanup:
        _cleanup_reports([json_path, xml_path])

    exit_code, logs, duration = _run_godot(
        project_root=project_root,
        godot_binary=godot_binary,
        extra_env={
            "CODEX_TEST_MANIFEST": str(manifest_path),
        },
    )

    summary, scripts = _load_json_results(json_path)
    _augment_with_xml(xml_path, scripts)

    run = ManifestRun(
        exit_code=exit_code,
        summary=summary,
        scripts=scripts,
        manifest_path=str(manifest_path),
        results_json=str(json_path) if json_path.exists() else None,
        results_xml=str(xml_path) if xml_path.exists() else None,
        duration=duration,
        logs=logs,
        attempt=attempt,
        max_attempts=max_attempts,
    )

    return run


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = _parse_args(argv)

    if not args.project_root:
        raise SystemExit("--project-root must be provided or CODEX_PROJECT_ROOT must be set")
    if not args.godot_binary:
        raise SystemExit("--godot-binary must be provided or CODEX_GODOT_BIN must be set")

    project_root = Path(args.project_root).resolve()
    godot_binary = Path(args.godot_binary).resolve()
    manifest_path = (project_root / args.manifest).resolve() if not os.path.isabs(args.manifest) else Path(args.manifest).resolve()
    json_path = (project_root / args.results_json).resolve() if not os.path.isabs(args.results_json) else Path(args.results_json).resolve()
    xml_path = (project_root / args.results_xml).resolve() if not os.path.isabs(args.results_xml) else Path(args.results_xml).resolve()

    attempts = max(1, int(args.max_retries))
    retry_delay = max(0.0, float(args.retry_delay))

    last_run: Optional[ManifestRun] = None
    for attempt in range(1, attempts + 1):
        run = _execute_attempt(
            attempt=attempt,
            max_attempts=attempts,
            project_root=project_root,
            godot_binary=godot_binary,
            manifest_path=manifest_path,
            json_path=json_path,
            xml_path=xml_path,
            cleanup=not args.keep_artifacts,
        )
        last_run = run

        print(run.human_summary())
        print(json.dumps(run.as_json(), indent=2), file=sys.stderr)

        if run.exit_code == 0:
            break
        if attempt < attempts:
            time.sleep(retry_delay)

    if args.output and last_run is not None:
        _persist_outputs(Path(args.output), last_run)

    return 0 if last_run is None else last_run.exit_code


if __name__ == "__main__":  # pragma: no cover - manual execution guard
    raise SystemExit(main())
