#!/usr/bin/env python3
"""Utility for inspecting GDScript files for parse errors.

This module walks through a provided directory (or single file) and attempts to
parse each ``.gd`` file using :mod:`gdtoolkit`.  When a parse error is
encountered the tool reports the location of the issue, along with a short
snippet of surrounding lines so it is easier to diagnose the problem.

The exit status is ``0`` when every checked file parses cleanly and ``1`` when
at least one error is encountered.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence

try:  # pragma: no cover - import guard is exercised at runtime
    from gdtoolkit.parser import parser as gdparser
except ImportError as exc:  # pragma: no cover - handled gracefully in CLI
    raise SystemExit(
        "gdtoolkit is required for this script. Install it with 'pip install gdtoolkit'."
    ) from exc

try:  # pragma: no cover - import guard is exercised at runtime
    from lark import exceptions as lark_exceptions
except ImportError as exc:  # pragma: no cover - handled gracefully in CLI
    raise SystemExit(
        "The 'lark' dependency is required. It is installed automatically with gdtoolkit."
    ) from exc


@dataclass
class ParseIssue:
    """Information about a parse error detected in a GDScript file."""

    path: Path
    message: str
    line: int | None
    column: int | None
    context: Sequence[str]

    def to_dict(self) -> dict:
        """Return a JSON-serialisable representation of the issue."""

        return {
            "path": str(self.path),
            "message": self.message,
            "line": self.line,
            "column": self.column,
            "context": list(self.context),
        }


def iter_gd_files(paths: Iterable[Path]) -> Iterable[Path]:
    """Yield all ``.gd`` files contained in ``paths``."""

    for root in paths:
        root = root.resolve()
        if root.is_file() and root.suffix == ".gd":
            yield root
        elif root.is_dir():
            for path in sorted(root.rglob("*.gd")):
                if path.is_file():
                    yield path


def read_context(path: Path, line: int | None, radius: int = 2) -> List[str]:
    """Return a snippet of text surrounding ``line`` in ``path``.

    When ``line`` is ``None`` the entire file is returned.
    """

    lines = path.read_text(encoding="utf-8").splitlines()
    if line is None:
        return lines

    start = max(line - 1 - radius, 0)
    end = min(line - 1 + radius, len(lines) - 1)
    snippet = []
    for idx in range(start, end + 1):
        snippet.append(f"{idx + 1:>5}: {lines[idx]}")
    return snippet


def parse_file(path: Path) -> List[ParseIssue]:
    """Attempt to parse ``path`` and return any issues that occur."""

    source = path.read_text(encoding="utf-8")
    try:
        gdparser.parse(source)
    except lark_exceptions.LarkError as error:
        line = getattr(error, "line", None)
        column = getattr(error, "column", None)
        message = str(error)
        context = read_context(path, line)
        return [ParseIssue(path=path, message=message, line=line, column=column, context=context)]
    return []


def collect_issues(paths: Iterable[Path]) -> List[ParseIssue]:
    """Gather parse issues for ``paths``."""

    issues: List[ParseIssue] = []
    for gd_file in iter_gd_files(paths):
        issues.extend(parse_file(gd_file))
    return issues


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        default=[Path.cwd()],
        help="File or directory paths to inspect. Defaults to the current working directory.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine readable JSON instead of human-readable text.",
    )
    parser.add_argument(
        "--context-radius",
        type=int,
        default=2,
        help="Number of lines of context to show around the offending line (default: %(default)s).",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    issues = collect_issues(args.paths)

    if args.json:
        print(json.dumps([issue.to_dict() for issue in issues], indent=2))
    else:
        if not issues:
            print("No parse issues detected.")
        else:
            for index, issue in enumerate(issues, 1):
                header = f"[{index}] {issue.path}"
                print(header)
                if issue.line is not None:
                    print(f"    line {issue.line}, column {issue.column}")
                print(f"    {issue.message}")
                for line in read_context(issue.path, issue.line, args.context_radius):
                    print(f"    {line}")
                print()
            print(f"Total issues found: {len(issues)}")

    return 0 if not issues else 1


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    sys.exit(main())
