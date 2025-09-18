#!/usr/bin/env python3
"""Normalise the WordlistPanel scene for headless test execution."""
from __future__ import annotations

from pathlib import Path

TSCN_PATH = Path("addons/platform_gui/panels/wordlist/WordlistPanel.tscn")

REPLACEMENTS = {
    "Control.SIZE_EXPAND_FILL": "3",
    "Control.SIZE_EXPAND": "2",
    "Control.SIZE_FILL": "1",
    "Control.FOCUS_ALL": "2",
    "ItemList.SELECT_MULTI": "1",
    "TextServer.AUTOWRAP_WORD_SMART": "3",
}

UNIQUE_NODES = {
    "RefreshButton",
    "ResourceList",
    "UseWeights",
    "DelimiterInput",
    "SeedInput",
    "PreviewButton",
    "PreviewOutput",
    "ValidationLabel",
    "MetadataSummary",
    "NotesLabel",
}


def ensure_unique_name(lines: list[str]) -> list[str]:
    result: list[str] = []
    total = len(lines)
    index = 0
    while index < total:
        line = lines[index]
        result.append(line)
        if line.startswith("[node ") and "name=\"" in line:
            name = line.split("name=\"")[1].split("\"")[0]
            if name in UNIQUE_NODES:
                has_flag = False
                lookahead = index + 1
                while lookahead < total:
                    next_line = lines[lookahead]
                    if next_line.startswith("["):
                        break
                    if "unique_name_in_owner" in next_line:
                        has_flag = True
                        break
                    if next_line.strip() == "":
                        # stop before blank separator
                        break
                    lookahead += 1
                if not has_flag:
                    result.append("unique_name_in_owner = true")
        index += 1
    return result


def main() -> None:
    text = TSCN_PATH.read_text(encoding="utf-8")
    for token, value in REPLACEMENTS.items():
        text = text.replace(token, value)
    lines = text.splitlines()
    updated_lines = ensure_unique_name(lines)
    new_text = "\n".join(updated_lines) + "\n"
    if new_text == text + ("\n" if not text.endswith("\n") else ""):
        print("No changes necessary.")
        return
    TSCN_PATH.write_text(new_text, encoding="utf-8")
    print("Updated", TSCN_PATH)


if __name__ == "__main__":
    main()
