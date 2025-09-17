# Diagnostics Catalog

The diagnostic manifest stored alongside this README defines scripted scenarios that highlight specific behaviours or guardrails in the name generator stack.

## Naming conventions

- **IDs** follow the `domain:subject:detail` format. Use descriptive nouns so downstream tooling can group related diagnostics (for example, `strategy:hybrid:overlap_window`).
- **Scripts** live under `tests/diagnostics/` and are named after their ID with underscores instead of colons (e.g. `strategy_hybrid_overlap_window.gd`).
- **Summaries** in the manifest should fit on a single line and explain why the diagnostic exists or what regression it catches.

## Expectations for new diagnostics

1. Implement the scenario as a standalone Godot script that exits via `quit()` and raises `push_error()` when validation fails.
2. Register the script in `manifest.json` with a unique ID, matching summary, and optional `tags` array if automation needs to filter the suite.
3. Update `devdocs/tooling.md` and other relevant guides when introducing new diagnostics so integrators understand how to trigger them.
