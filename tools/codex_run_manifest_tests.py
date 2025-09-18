"""CLI helper for running the Godot manifest driven test suite under Codex.

This module provides a small command line interface that shells out to Godot
via :class:`tools.codex_godot_process_manager.CodexGodotProcessManager`.  It is
designed to mirror the automation hooks used by Codex operators so that local
developers can easily reproduce and debug failing manifest suites.

The entry point performs the following high level workflow:

* Reset any stale ``tests/results.*`` artifacts to avoid confusing Codex with
  old reports.
* Launch one or more headless Godot instances using the manifest group runner
  scripts (``run_generator_tests.gd``, ``run_diagnostics_tests.gd``, and
  ``run_platform_gui_tests.gd``). Each run emits JSON and optional JUnit style
  reports that the script merges after the engine exits.
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
from typing import Any, Dict, Iterable, List, Optional, Sequence
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
    group: Optional[str] = None

    @property
    def status(self) -> str:
        return "PASS" if self.passed else "FAIL"


@dataclass
class ManifestSummary:
    """Aggregated statistics produced by the manifest group runners."""

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
                    "group": script.group,
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
                if script.group:
                    detail = f"{detail} [group: {script.group}]"
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
        help="Path to the manifest consumed by the Godot manifest runners.",
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
    parser.add_argument(
        "--group",
        choices=["generator_core", "diagnostics", "platform_gui"],
        help="Restrict execution to a single manifest group.",
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


MANIFEST_GROUP_SCRIPTS: Dict[str, str] = {
    "generator_core": "res://tests/run_generator_tests.gd",
    "diagnostics": "res://tests/run_diagnostics_tests.gd",
    "platform_gui": "res://tests/run_platform_gui_tests.gd",
}


def _run_godot(
    *,
    project_root: Path,
    godot_binary: Path,
    script_path: str,
    extra_env: Optional[Dict[str, str]] = None,
) -> tuple[int, List[Dict[str, str]], float]:
    """Launch Godot using the process manager and wait for completion."""

    manager = CodexGodotProcessManager(
        godot_binary=str(godot_binary),
        project_root=str(project_root),
        extra_args=["--script", script_path, "--quit"],
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


def _load_json_results(path: Path) -> tuple[ManifestSummary, List[ScriptReport], Dict[str, Any]]:
    if not path.exists():
        return ManifestSummary(error=f"JSON results missing at {path}"), [], {}

    data = json.loads(path.read_text(encoding="utf-8"))
    payload: Dict[str, Any] = data if isinstance(data, dict) else {}
    summary_data = payload.get("summary", {}) if isinstance(payload.get("summary"), dict) else {}
    tests_data = payload.get("tests", []) if isinstance(payload.get("tests"), list) else []

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

    return summary, scripts, payload


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


def _load_xml_root(path: Path) -> Optional[ElementTree.Element]:
    if not path.exists():
        return None

    try:
        return ElementTree.fromstring(path.read_text(encoding="utf-8"))
    except ElementTree.ParseError:
        return None


def _merge_junit_roots(roots: Sequence[ElementTree.Element]) -> Optional[ElementTree.Element]:
    suites: List[ElementTree.Element] = []
    for root in roots:
        if root.tag == "testsuite":
            suites.append(root)
        elif root.tag == "testsuites":
            suites.extend(list(root))

    if not suites:
        return None

    merged = ElementTree.Element("testsuites")

    totals = {"tests": 0, "failures": 0, "errors": 0, "skipped": 0}
    total_time = 0.0

    for suite in suites:
        clone = ElementTree.fromstring(ElementTree.tostring(suite, encoding="utf-8"))
        merged.append(clone)

        for key in totals:
            try:
                totals[key] += int(float(suite.get(key, "0")))
            except ValueError:
                continue

        try:
            total_time += float(suite.get("time", "0"))
        except ValueError:
            continue

    for key, value in totals.items():
        merged.set(key, str(value))
    merged.set("time", f"{total_time:.6f}")

    return merged


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
    group: Optional[str],
) -> ManifestRun:
    groups_to_run = [group] if group else list(MANIFEST_GROUP_SCRIPTS.keys())

    aggregated_summary = ManifestSummary()
    aggregated_scripts: List[ScriptReport] = []
    aggregated_logs: List[Dict[str, str]] = []
    aggregated_duration = 0.0
    aggregated_exit_code = 0
    raw_json_payload: Dict[str, Any] = {
        "summary": {
            "scripts_passed": 0,
            "scripts_failed": 0,
            "assertions": 0,
            "error": None,
        },
        "tests": [],
    }
    xml_roots: List[ElementTree.Element] = []

    for group_name in groups_to_run:
        if cleanup:
            _cleanup_reports([json_path, xml_path])

        script_path = MANIFEST_GROUP_SCRIPTS[group_name]
        exit_code, logs, duration = _run_godot(
            project_root=project_root,
            godot_binary=godot_binary,
            script_path=script_path,
            extra_env={
                "CODEX_TEST_MANIFEST": str(manifest_path),
                "CODEX_MANIFEST_GROUP": group_name,
            },
        )

        aggregated_exit_code = max(aggregated_exit_code, exit_code)
        aggregated_duration += duration

        for log in logs:
            entry = dict(log)
            entry.setdefault("group", group_name)
            aggregated_logs.append(entry)

        summary, scripts, raw_payload = _load_json_results(json_path)
        for script in scripts:
            script.group = group_name
        _augment_with_xml(xml_path, scripts)

        xml_root = _load_xml_root(xml_path)
        if xml_root is not None:
            xml_roots.append(xml_root)

        aggregated_summary.scripts_passed += summary.scripts_passed
        aggregated_summary.scripts_failed += summary.scripts_failed
        aggregated_summary.assertions += summary.assertions

        if summary.error:
            tagged_error = f"{group_name}: {summary.error}"
            if aggregated_summary.error:
                aggregated_summary.error = f"{aggregated_summary.error}; {tagged_error}"
            else:
                aggregated_summary.error = tagged_error

        aggregated_scripts.extend(scripts)

        tests_array = raw_payload.get("tests")
        if isinstance(tests_array, list):
            merged_tests = raw_json_payload.get("tests")
            if not isinstance(merged_tests, list):
                merged_tests = []
                raw_json_payload["tests"] = merged_tests
            for entry in tests_array:
                if isinstance(entry, dict):
                    merged_entry: Dict[str, Any] = dict(entry)
                    merged_entry.setdefault("group", group_name)
                    merged_tests.append(merged_entry)

        raw_summary = raw_payload.get("summary")
        summary_payload = raw_json_payload.get("summary")
        if not isinstance(summary_payload, dict):
            summary_payload = {}
            raw_json_payload["summary"] = summary_payload
        if isinstance(raw_summary, dict):
            summary_payload["scripts_passed"] = int(summary_payload.get("scripts_passed", 0) or 0) + int(raw_summary.get("scripts_passed", 0) or 0)
            summary_payload["scripts_failed"] = int(summary_payload.get("scripts_failed", 0) or 0) + int(raw_summary.get("scripts_failed", 0) or 0)
            summary_payload["assertions"] = int(summary_payload.get("assertions", 0) or 0) + int(raw_summary.get("assertions", 0) or 0)

    summary_payload = raw_json_payload.get("summary")
    if not isinstance(summary_payload, dict):
        summary_payload = {}
        raw_json_payload["summary"] = summary_payload
    summary_payload["scripts_passed"] = aggregated_summary.scripts_passed
    summary_payload["scripts_failed"] = aggregated_summary.scripts_failed
    summary_payload["assertions"] = aggregated_summary.assertions
    summary_payload["error"] = aggregated_summary.error

    results_json_path: Optional[str] = None
    if groups_to_run:
        json_path.write_text(json.dumps(raw_json_payload, indent=2) + "\n", encoding="utf-8")
        results_json_path = str(json_path)

    results_xml_path: Optional[str] = None
    if xml_roots:
        merged_xml = _merge_junit_roots(xml_roots)
        if merged_xml is not None:
            xml_text = ElementTree.tostring(merged_xml, encoding="unicode")
            xml_path.write_text(xml_text + "\n", encoding="utf-8")
            results_xml_path = str(xml_path)

    run = ManifestRun(
        exit_code=aggregated_exit_code,
        summary=aggregated_summary,
        scripts=aggregated_scripts,
        manifest_path=str(manifest_path),
        results_json=results_json_path,
        results_xml=results_xml_path,
        duration=aggregated_duration,
        logs=aggregated_logs,
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
            group=args.group,
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
