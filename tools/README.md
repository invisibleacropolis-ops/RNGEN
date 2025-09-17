# GDScript Parse Helper

The `gdscript_parse_helper.py` utility makes it easy to locate and resolve
GDScript parse errors across this repository.

## Features

- Recursively discovers every `.gd` file under the directories you point it to.
- Uses [`gdtoolkit`](https://github.com/Scony/godot-gdscript-toolkit) to parse
  files, matching the behaviour of the Godot editor.
- Reports the file, line, column, and message for each parse failure.
- Prints the surrounding source lines so that issues can be fixed rapidly.
- Supports a machine-readable JSON output mode for integration into other
  tooling.

## Installation

The tool depends on the [`gdtoolkit`](https://pypi.org/project/gdtoolkit/)
package.  Install it into your virtual environment (or the current Python
interpreter) with:

```bash
pip install gdtoolkit
```

The repository already ships with `gdtoolkit` in the development environment
used for this change, but it is listed here for completeness.

## Usage

From the repository root run:

```bash
python tools/gdscript_parse_helper.py
```

By default the script scans the current working directory.  You can provide one
or more paths to limit the search scope:

```bash
python tools/gdscript_parse_helper.py addons/name_generator
```

Use `--json` to emit machine-readable output, or `--context-radius` to control
how many lines of source are displayed around each error:

```bash
python tools/gdscript_parse_helper.py --context-radius 4 --json
```

The process exits with status code `0` when no parse errors were found and `1`
otherwise.  This makes it suitable for CI pipelines and pre-commit hooks.

## Troubleshooting Workflow

1. Run the helper script and note each reported parse error.
2. Inspect the surrounding context that the tool prints to understand the
   problem.
3. Apply the fix in your editor of choice.
4. Rerun the helper to confirm the error is resolved before committing.

Repeat steps 2–4 until the command finishes without errors.  When combined with
Godot's own error messages this script provides a fast feedback loop for keeping
GDScript clean and parseable.
