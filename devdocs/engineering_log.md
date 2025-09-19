# Engineering Log

## 2025-09-18
- **Project configuration** – Confirmed the Godot `project.godot` autoload section still registers the `RNGManager`, `NameGenerator`, and `RNGProcessor` singletons required by the Platform GUI workflows.
- **Platform GUI validation** – Unable to launch the scene because the `godot4` executable is not present in the current environment; no runtime verification of the Generators, Seeds, or Debug Logs tabs was possible. Downstream tasks will need a workstation with Godot 4.4 installed to complete the handbook walkthrough.
- **Follow-up actions** – Once Godot 4.4 is available, re-run the Platform GUI workflow to confirm UI behaviour matches `devdocs/platform_gui_handbook.md`, paying particular attention to DebugRNG recording options.

## 2025-09-19
- **Scroll container regression** – Restored vertical scrolling in `Main_Interface.tscn` by letting the `VBoxContainer` compute its natural height, forcing the scroll bar to show automatically, and allowing nested tab containers to forward mouse wheel input to the parent scroll view.
- **Headless RNG coverage** – `Main_Interface.gd` now provisions a local `RNGProcessor` singleton when the autoload fails to materialise so GUI panels run without warnings in isolated test scenes.
- **Manifest automation** – `tests/run_platform_gui_tests.gd` exports the aggregated summary to `tests/results.json`, enabling `python tools/codex_run_manifest_tests.py` to report accurate pass/fail totals for Codex operators.
