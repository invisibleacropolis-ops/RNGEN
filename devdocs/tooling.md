# Tooling Reference

The `name_generator/tools/` directory collects self-contained Godot scripts that assist with data authoring and manual QA. Run them from the repository root with the Godot command-line interface:

```bash
godot --headless --path . --script res://name_generator/tools/<script_name>.gd
```

## dataset_inspector.gd

`dataset_inspector.gd` traverses the `res://data/` directory and prints a summary of each dataset folder. Use it to spot empty directories or confirm that new word lists have been imported correctly.

Expected output:

- A bullet for every child directory under `data/` (e.g. `markov_models`, `syllable_sets`).
- Warnings when a folder is missing or empty, allowing data authors to rectify issues before running strategies.

## Creating new tooling scripts

1. Place the script under `name_generator/tools/` and extend `SceneTree` so it can quit cleanly via `quit()`.
2. Parse command-line arguments with `OS.get_cmdline_args()` when you need additional parameters (such as output paths or filters).
3. Reuse helper utilities from `name_generator/utils/` where possible to keep behaviour deterministic and testable.
4. Document new scripts here and add usage examples to the root `README.md` to keep workflows discoverable.
