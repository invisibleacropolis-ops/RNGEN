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

## Diagnostics manifest

The headless diagnostic runner (`tests/run_script_diagnostic.gd`) reads from `tests/diagnostics/manifest.json`. Each manifest entry maps a stable `id` to the Godot script that exercises a focused scenario, alongside a short `summary` to help triage failures quickly. Use the colon-delimited format `domain:subject:detail` when minting IDs—e.g. `strategy:hybrid:overlap_window` evaluates the hybrid generator's overlap window safeguards.

List the available IDs directly from the manifest to confirm coverage or to feed into automation:

```bash
jq -r '.diagnostics[].id + "\t" + .summary' tests/diagnostics/manifest.json
```

Automation and local scripts can invoke the runner headlessly by forwarding the chosen ID after a double dash so Godot preserves the argument:

```bash
godot --headless --script res://tests/run_script_diagnostic.gd -- strategy:hybrid:overlap_window
```

The runner exits with a non-zero status code when a diagnostic fails, making it suitable for CI pipelines or pre-commit hooks.
