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

## QA panel and regression workflows

The Platform GUI now ships with a dedicated QA panel (`addons/platform_gui/panels/qa/QAPanel.tscn`) that wraps the controller's orchestration helpers. From inside the editor you can:

- Launch the full regression manifest via the **Run Full Suite** action, which calls `run_all_tests.gd` through the controller and streams the console output directly into the panel log view as lines arrive.【F:addons/platform_gui/panels/qa/QAPanel.gd†L4-L115】【F:addons/platform_gui/controllers/RNGProcessorController.gd†L180-L261】
- Trigger focused checks with the **Run Diagnostic** button. Diagnostics are populated from `RNGProcessorController.get_available_qa_diagnostics()` so only manifest-backed scenarios appear in the dropdown.【F:addons/platform_gui/panels/qa/QAPanel.gd†L116-L214】【F:addons/platform_gui/controllers/RNGProcessorController.gd†L118-L158】
- Review recent executions from the history list. Each record includes exit status, timestamps, and a persisted log path. Selecting an entry restores the status summary, exposes the saved log, and enables **Open Log** for quick access to the captured Godot output.【F:addons/platform_gui/panels/qa/QAPanel.gd†L215-L330】【F:addons/platform_gui/controllers/RNGProcessorController.gd†L320-L408】

When regressions occur, capture both the streamed panel log and the generated DebugRNG exports surfaced through the linked Logs tab so triage has deterministic reproduction artefacts.【F:addons/platform_gui/panels/qa/QAPanel.gd†L46-L55】 Store these alongside ticket attachments or CI artefacts for cross-team debugging.

### Running suites headlessly

The QA panel forwards requests to the shared regression runner at `tests/test_suite_runner.gd`, ensuring GUI launches and headless scripts share the same execution path and log summaries.【F:addons/platform_gui/controllers/RNGProcessorController.gd†L232-L344】【F:tests/test_suite_runner.gd†L1-L160】 To reproduce the panel's behaviour without the GUI (e.g., in CI or on remote agents), invoke the Godot CLI directly from the repository root:

```bash
godot --headless --path . --script res://tests/run_all_tests.gd
```

Always archive the stdout/stderr stream from this command. The runner streams progress line-by-line and concludes with a structured summary containing exit code, manifest coverage counts, and any failing suites—critical context for support engineers consuming CI artefacts.【F:tests/run_all_tests.gd†L1-L141】【F:tests/test_suite_runner.gd†L94-L160】

### Diagnostics manifest

The headless diagnostic runner (`tests/run_script_diagnostic.gd`) reads from `tests/diagnostics/manifest.json`. Each manifest entry maps a stable `id` to the Godot script that exercises a focused scenario, alongside a short `summary` to help triage failures quickly. Use the colon-delimited format `domain:subject:detail` when minting IDs—e.g. `strategy:hybrid:overlap_window` evaluates the hybrid generator's overlap window safeguards.

List the available IDs directly from the manifest to confirm coverage or to feed into automation:

```bash
jq -r '.diagnostics[].id + "\t" + .summary' tests/diagnostics/manifest.json
```

Automation and local scripts can invoke the runner headlessly by forwarding the chosen ID after a double dash so Godot preserves the argument:

```bash
godot --headless --script res://tests/run_script_diagnostic.gd -- strategy:hybrid:overlap_window
```

The runner exits with a non-zero status code when a diagnostic fails, making it suitable for CI pipelines or pre-commit hooks. Capture the full console transcript and attach it to bug reports so the GUI history and CI pipelines remain in sync.
