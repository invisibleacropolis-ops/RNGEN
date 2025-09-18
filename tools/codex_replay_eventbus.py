"""Codex helpers for replaying EventBus transcripts headlessly.

This module builds on :mod:`tools.codex_godot_process_manager` to launch the
``eventbus_replay_runner.gd`` SceneTree script, stream the structured JSON
messages it emits, and aggregate a machine-readable report that outside
engineers can consume.  The helper mirrors the behaviour that Codex uses in CI
so manual operators can diagnose issues locally with the same tooling.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence

from .codex_godot_process_manager import CodexGodotProcessManager

DEFAULT_REPLAY_SCRIPT = "res://tests/eventbus_replay_runner.gd"


@dataclass
class ReplayEntry:
    """Represents a single replay attempt emitted by the harness."""

    index: int
    signal_name: str
    status: str
    message: str
    timestamp: Optional[str] = None


@dataclass
class ReplayReport:
    """Aggregated report describing the outcome of a replay run."""

    entries: List[ReplayEntry] = field(default_factory=list)
    summary: Dict[str, object] = field(default_factory=dict)
    diagnostics: List[Dict[str, object]] = field(default_factory=list)
    logs: List[Dict[str, object]] = field(default_factory=list)
    log_export_path: Optional[str] = None
    echoed_log: Optional[str] = None

    @property
    def success(self) -> bool:
        """Return ``True`` when the harness reported a clean replay."""

        exit_code = int(self.summary.get("exit_code", 1))
        return exit_code == 0


def replay_eventbus_transcript(
    replay_path: Path | str,
    *,
    export_log_path: Path | str | None = None,
    echo_log: bool = False,
    extra_godot_args: Optional[Sequence[str]] = None,
    manager_kwargs: Optional[Dict[str, object]] = None,
    replay_script: str = DEFAULT_REPLAY_SCRIPT,
) -> ReplayReport:
    """Run the EventBus replay harness and return a structured report.

    Parameters
    ----------
    replay_path:
        Filesystem path to the JSON transcript that should be replayed.
    export_log_path:
        Optional path where the harness log should be exported on success.
    echo_log:
        When ``True`` the harness echoes its RichText transcript through the
        JSON stream so it can be surfaced in terminal output.
    extra_godot_args:
        Additional command line arguments forwarded to Godot *before* the
        ``-s`` flag.  Use this sparingly – the helper automatically injects the
        replay runner path and transcript parameters.
    manager_kwargs:
        Optional keyword arguments forwarded to
        :class:`CodexGodotProcessManager`.  ``extra_args`` should not be
        provided here; use :paramref:`extra_godot_args` instead.
    replay_script:
        Override the path to the replay runner script.  Defaults to
        :data:`DEFAULT_REPLAY_SCRIPT`.
    """

    transcript = Path(replay_path)
    if not transcript.exists():
        raise FileNotFoundError(f"Replay transcript not found: {transcript}")

    command: List[str] = list(extra_godot_args or [])
    command.extend(["-s", replay_script, str(transcript)])
    if export_log_path is not None:
        command.extend(["--export-log", str(export_log_path)])
    if echo_log:
        command.append("--echo-log")

    manager_config = dict(manager_kwargs or {})
    if "extra_args" in manager_config:
        raise ValueError(
            "Pass extra Godot CLI arguments via extra_godot_args instead of manager_kwargs['extra_args']."
        )

    report = ReplayReport()
    with CodexGodotProcessManager(extra_args=command, **manager_config) as manager:
        message_iterator = manager.iter_messages(timeout=0.1)
        while True:
            try:
                message = next(message_iterator)
            except StopIteration:
                break

            message_type = message.get("type")
            if message_type == "eventbus_replay_entry":
                report.entries.append(
                    ReplayEntry(
                        index=int(message.get("index", 0)),
                        signal_name=str(message.get("signal_name", "")),
                        status=str(message.get("status", "")),
                        message=str(message.get("message", "")),
                        timestamp=message.get("timestamp"),
                    )
                )
            elif message_type == "eventbus_replay_summary":
                report.summary = message
                break
            elif message_type == "eventbus_replay_log_export":
                report.log_export_path = str(message.get("path"))
            elif message_type == "eventbus_replay_log":
                report.logs.append(message)
            elif message_type == "eventbus_replay_echo":
                report.echoed_log = str(message.get("text", ""))
            elif message_type == "eventbus_replay_error":
                report.summary = message
                break
            else:
                report.diagnostics.append(message)

        report.diagnostics.extend(list(manager.iter_stderr_diagnostics()))

    return report


def format_report(report: ReplayReport) -> str:
    """Render a human readable summary for terminal output."""

    lines = []
    lines.append("EventBus Replay Summary")
    lines.append("=======================")
    lines.append(
        f"Status: {'OK' if report.success else 'FAILED'} | "
        f"Entries: {report.summary.get('total', len(report.entries))} | "
        f"Succeeded: {report.summary.get('succeeded', 0)} | "
        f"Failed: {report.summary.get('failed', 0)} | "
        f"Skipped: {report.summary.get('skipped', 0)}"
    )
    if report.log_export_path:
        lines.append(f"Log exported to: {report.log_export_path}")
    if report.echoed_log:
        lines.append("\nHarness Log:")
        lines.append(report.echoed_log)
    if report.entries:
        lines.append("\nEntries:")
        for entry in report.entries:
            lines.append(
                f"  [{entry.index:02d}] {entry.signal_name or 'n/a'} -> {entry.status.upper()} | {entry.message}"
            )
    if report.logs:
        lines.append("\nHarness Messages:")
        for log in report.logs:
            lines.append(json.dumps(log, sort_keys=True))
    if report.diagnostics:
        lines.append("\nDiagnostics:")
        for diagnostic in report.diagnostics:
            lines.append(json.dumps(diagnostic, sort_keys=True))
    return "\n".join(lines)


__all__ = [
    "ReplayEntry",
    "ReplayReport",
    "replay_eventbus_transcript",
    "format_report",
]


if __name__ == "__main__":  # pragma: no cover - convenience CLI
    import argparse

    parser = argparse.ArgumentParser(description="Replay EventBus transcripts headlessly via Codex.")
    parser.add_argument("replay", type=Path, help="Path to the replay JSON file.")
    parser.add_argument("--export-log", dest="export_log", type=Path, help="Optional path to export the harness log.")
    parser.add_argument(
        "--echo-log",
        dest="echo_log",
        action="store_true",
        help="Echo the harness log back to stdout after the replay completes.",
    )
    args = parser.parse_args()

    report = replay_eventbus_transcript(
        args.replay,
        export_log_path=args.export_log,
        echo_log=args.echo_log,
    )
    print(format_report(report))
    raise SystemExit(0 if report.success else 1)
