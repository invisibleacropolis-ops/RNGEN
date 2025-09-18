"""Codex oriented preflight checks for Godot automation workflows.

This module stitches together the lightweight :mod:`gdscript_parse_helper`
scanner with the heavier manifest runner exposed via
``tools.codex_run_manifest_tests``.  Codex operators typically want a single
entry point that can reject obviously broken GDScript before the costlier
engine boot, yet also continue straight into the manifest suite when the parse
phase succeeds.  The command line here mirrors that workflow:

* Walk the provided paths (defaulting to the current working directory) and
  collect parse issues for every ``.gd`` file.
* Emit Codex friendly JSON with enriched context snippets by default, while
  providing a human readable fallback for manual debugging sessions.
* Optionally invoke ``codex_run_manifest_tests`` with user supplied arguments
  when no parse failures are detected so automation can orchestrate the entire
  validation flow from one command.
* Surface aggregated telemetry covering scripts scanned, parse failures, and
  manifest coverage so the Codex orchestrator can make fast decisions without
  parsing free-form logs.

Outside engineers can run this script directly or embed it into custom tooling
when building review automation.  Use ``--human`` for a concise textual summary
or ``--manifest-args -- <args>`` to forward options to the manifest runner.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Sequence

from gdscript_parse_helper import collect_issues, iter_gd_files, read_context

from tools import codex_run_manifest_tests as manifest_runner


@dataclass
class ParseResult:
    """Container describing the outcome of the parse stage."""

    scripts_scanned: int
    issues: List[dict]

    @property
    def failure_count(self) -> int:
        return len(self.issues)


@dataclass
class ManifestResult:
    """Summary information extracted from the manifest runner."""

    exit_code: int
    payload: Optional[dict]

    @property
    def scripts_total(self) -> Optional[int]:
        if not self.payload:
            return None
        summary = self.payload.get("summary", {})
        return summary.get("scripts_passed", 0) + summary.get("scripts_failed", 0)

    @property
    def scripts_failed(self) -> Optional[int]:
        if not self.payload:
            return None
        return self.payload.get("summary", {}).get("scripts_failed")

    @property
    def scripts_passed(self) -> Optional[int]:
        if not self.payload:
            return None
        return self.payload.get("summary", {}).get("scripts_passed")


def _parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        default=[Path.cwd()],
        help="Files or directories to inspect for .gd scripts (defaults to the working directory).",
    )
    parser.add_argument(
        "--context-radius",
        type=int,
        default=2,
        help="Number of surrounding lines to include in context snippets (default: %(default)s).",
    )
    parser.add_argument(
        "--human",
        action="store_true",
        help="Emit a human friendly summary instead of JSON (useful for manual debugging).",
    )
    parser.add_argument(
        "--skip-parse",
        action="store_true",
        help="Skip the GDScript parse phase (useful when only running manifest tests).",
    )
    parser.add_argument(
        "--skip-manifest",
        action="store_true",
        help="Do not invoke the manifest runner even if parsing succeeds.",
    )
    parser.add_argument(
        "--manifest-args",
        nargs=argparse.REMAINDER,
        help="Arguments forwarded to tools/codex_run_manifest_tests.py (prefix with '--').",
    )
    return parser.parse_args(argv)


def _normalise_paths(paths: Iterable[Path]) -> List[Path]:
    return [path.resolve() for path in paths]


def _run_parse_stage(paths: List[Path], context_radius: int) -> ParseResult:
    scripts = list(iter_gd_files(paths))
    issues = collect_issues(paths)
    enriched = []
    for issue in issues:
        enriched.append(
            {
                "path": str(issue.path),
                "message": issue.message,
                "line": issue.line,
                "column": issue.column,
                "context": read_context(issue.path, issue.line, context_radius),
            }
        )
    return ParseResult(scripts_scanned=len(scripts), issues=enriched)


def _decode_json_stream(stream: str) -> List[dict]:
    """Extract JSON objects from ``stream`` using a tolerant decoder."""

    decoder = json.JSONDecoder()
    idx = 0
    payloads: List[dict] = []
    length = len(stream)
    while idx < length:
        while idx < length and stream[idx] in "\r\n \t":
            idx += 1
        if idx >= length:
            break
        try:
            payload, offset = decoder.raw_decode(stream, idx)
        except json.JSONDecodeError:
            break
        payloads.append(payload)
        idx = offset
    return payloads


def _run_manifest(manifest_args: Sequence[str]) -> ManifestResult:
    stderr_buffer = io.StringIO()
    with contextlib.redirect_stderr(stderr_buffer):
        exit_code = manifest_runner.main(manifest_args)

    captured = stderr_buffer.getvalue()
    if captured:
        sys.stderr.write(captured)
        sys.stderr.flush()

    payloads = _decode_json_stream(captured)
    payload = payloads[-1] if payloads else None
    return ManifestResult(exit_code=exit_code, payload=payload)


def _build_json_output(
    parse_result: Optional[ParseResult],
    manifest_result: Optional[ManifestResult],
    telemetry: dict,
) -> str:
    status = "passed"
    if telemetry.get("parse_failures"):
        status = "failed"
    elif (
        manifest_result is not None
        and manifest_result.exit_code is not None
        and manifest_result.exit_code != 0
    ):
        status = "failed"

    payload = {
        "status": status,
        "telemetry": telemetry,
    }

    if parse_result is not None:
        payload["parse"] = {
            "scripts_scanned": parse_result.scripts_scanned,
            "issues": parse_result.issues,
        }
    else:
        payload["parse"] = {"skipped": True}

    if manifest_result is not None:
        manifest_payload = {
            "exit_code": manifest_result.exit_code,
        }
        if manifest_result.payload is not None:
            manifest_payload["summary"] = manifest_result.payload.get("summary")
            manifest_payload["scripts"] = manifest_result.payload.get("scripts")
        payload["manifest"] = manifest_payload
    else:
        payload["manifest"] = {"skipped": True}

    return json.dumps(payload, indent=2)


def _build_human_output(
    parse_result: Optional[ParseResult],
    manifest_result: Optional[ManifestResult],
    telemetry: dict,
) -> str:
    lines = [
        "Codex preflight summary:",
        f"  Scripts scanned: {telemetry.get('scripts_scanned', 0)}",
        f"  Parse failures: {telemetry.get('parse_failures', 0)}",
    ]

    manifest_attempted = telemetry.get("manifest_attempted", False)
    if manifest_attempted:
        lines.append(
            f"  Manifest exit code: {telemetry.get('manifest_exit_code', 'n/a')}"
        )
        if manifest_result and manifest_result.payload:
            lines.append(
                f"  Manifest coverage: {manifest_result.scripts_passed}/{manifest_result.scripts_total} scripts passed"
            )
    else:
        lines.append("  Manifest runner: skipped")

    if parse_result and parse_result.issues:
        lines.append("")
        lines.append("Parse issues detected:")
        for index, issue in enumerate(parse_result.issues, 1):
            lines.append(f"  [{index}] {issue['path']}")
            if issue["line"] is not None:
                lines.append(
                    f"      line {issue['line']}, column {issue['column']}"
                )
            lines.append(f"      {issue['message']}")
            for context_line in issue["context"]:
                lines.append(f"      {context_line}")
    elif parse_result is None:
        lines.append("")
        lines.append("Parse stage skipped by request.")

    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)

    manifest_args = args.manifest_args or []
    if manifest_args and manifest_args[0] == "--":
        manifest_args = manifest_args[1:]
    parse_result: Optional[ParseResult] = None
    manifest_result: Optional[ManifestResult] = None

    telemetry = {
        "scripts_scanned": 0,
        "parse_failures": 0,
        "manifest_attempted": False,
        "manifest_exit_code": None,
    }

    if not args.skip_parse:
        paths = _normalise_paths(args.paths)
        parse_result = _run_parse_stage(paths, args.context_radius)
        telemetry["scripts_scanned"] = parse_result.scripts_scanned
        telemetry["parse_failures"] = parse_result.failure_count
    else:
        parse_result = None

    should_run_manifest = (
        not args.skip_manifest
        and (args.skip_parse or telemetry["parse_failures"] == 0)
    )

    if should_run_manifest:
        telemetry["manifest_attempted"] = True
        manifest_result = _run_manifest(manifest_args)
        telemetry["manifest_exit_code"] = manifest_result.exit_code
        if manifest_result.payload:
            telemetry["manifest_scripts_total"] = manifest_result.scripts_total
            telemetry["manifest_scripts_failed"] = manifest_result.scripts_failed
            telemetry["manifest_scripts_passed"] = manifest_result.scripts_passed
    else:
        telemetry["manifest_exit_code"] = None

    output = (
        _build_human_output(parse_result, manifest_result, telemetry)
        if args.human
        else _build_json_output(parse_result, manifest_result, telemetry)
    )
    print(output)

    if telemetry["parse_failures"]:
        return 1
    if should_run_manifest and manifest_result and manifest_result.exit_code:
        return manifest_result.exit_code
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    sys.exit(main())
