# Platform GUI Artist Handbook

## Purpose and scope

The Platform GUI is the artist-facing control centre for deterministic name generation. It lets art and narrative teams experiment with generator strategies, run batch jobs with predictable seeds, and inspect the same DebugRNG telemetry that support engineers rely on when triaging issues. Everything the interface does is powered by the `RNGProcessor` middleware documented in [`devdocs/rng_processor_manual.md`](./rng_processor_manual.md); this guide explains the GUI in artist-friendly language and shows how each button maps to a middleware capability.

## Launch checklist

Follow these steps whenever you need to work inside the Platform GUI:

1. **Open the Godot project** – Launch Godot 4.4 and open `project.godot` from the repository root. The GUI scene tree expects the `RNGProcessor` autoload to be active, so do not create a blank project or rename the root folder.
2. **Confirm autoloads** – In the Godot editor, open **Project > Project Settings > Autoload** and verify that `RNGManager`, `NameGenerator`, and `RNGProcessor` are all enabled. These singletons are the bridges between the GUI and the middleware. If any are missing, press the refresh icon to reload project settings or re-add them by pointing to the corresponding `.gd` files in `res://autoloads/`.
3. **Run the GUI scene** – Press <kbd>F5</kbd> (or click the play icon) to launch the default scene. The Platform GUI window should appear with tabs for *Generators*, *Seeds*, and *Debug Logs*.
4. **Optional: enable DebugRNG logging** – If you want the GUI to collect detailed telemetry, toggle the "Record DebugRNG Session" option in the toolbar before running any generators. This attaches the helper via `RNGProcessor.set_debug_rng(...)` so the middleware starts writing the session report immediately.

## Common workflows

### Running a generator

1. Open the **Generators** tab. The strategy dropdown is populated via `RNGProcessor.list_strategies()`, so the list always matches what the middleware advertises.
2. Select a strategy. The configuration form and helper text are fetched from `RNGProcessor.describe_strategy(id)`, ensuring the GUI validates inputs using the same schema the middleware expects.
3. Enter the desired parameters. Required fields are highlighted and include inline descriptions written for narrative teams.
4. Press **Generate**. The GUI calls `RNGProcessor.generate(config)` behind the scenes. While the middleware processes the request, the interface shows a status spinner driven by the `generation_started` signal.
5. Review the result. Successful runs display the returned payload alongside the resolved seed and RNG stream name reported by `generation_completed`. If the middleware emits `generation_failed`, the GUI surfaces the human-readable error message plus suggested fixes.

### Configuring word list strategies

1. Choose **Word List** from the strategy dropdown to load the dedicated panel.
2. Review the metadata banner above the form: the required and optional keys are sourced from the cached middleware schema so you know which fields must be filled before generating.
3. Use the resource browser to select one or more `WordListResource` assets. Each entry shows locale, domain, and whether weighting data is available so you can mix compatible lists at a glance.
4. Toggle **Use weights when available** if you want the middleware to respect weighted entries for every selected resource.
5. Adjust the delimiter field to control how sampled values are joined. Leaving the input blank defaults to a single space.
6. Provide an optional seed label in the preview row. The panel passes it straight to `RNGProcessor.generate(...)` so repeat previews with the same seed remain deterministic.
7. Press **Preview** to request a seeded sample from the middleware. Successful runs render the preview inline, while validation errors appear in red beneath the controls so you can correct the form without leaving the panel.
8. Click **Refresh** if you add new word lists to the project mid-session. The button reloads both the metadata schema and the resource catalogue.

### Reviewing DebugRNG logs

1. Switch to the **Debug Logs** tab. When DebugRNG is active, the middleware writes to `user://debug_rng_report.txt` (or a custom path you configured earlier).
2. Click **Refresh Log**. This button requests the latest telemetry via `RNGProcessor.get_debug_rng().read_current_log()` and updates the viewer pane.
3. Use the sidebar filters to jump to specific sections (Generation Timeline, Stream Usage, Warnings). These anchors mirror the log layout described in the middleware manual, helping you confirm whether unexpected results came from seeds, strategy choices, or warnings recorded by `record_warning(...)`.
4. Press **Download Log** to save a copy. The GUI calls `DebugRNG.close()` through the middleware so the file flushes to disk before presenting the system file picker.

### Replaying a seed

1. Navigate to the **Seeds** tab. The current master seed is displayed by calling `RNGProcessor.get_master_seed()`.
2. To replay a past result, paste the saved seed into the input box and click **Apply Seed**. The GUI forwards the value to `RNGProcessor.set_master_seed(seed_value)`, ensuring every subsequent generator run reuses that exact seed.
3. Need a fresh deterministic run? Click **Randomize Seed**. This invokes `RNGProcessor.reset_master_seed()`, updates the display, and copies the new value to your clipboard so you can store it alongside exported art.
4. For context on derived streams (e.g., when multiple generators run concurrently), open the Debug Logs tab and examine the Stream Usage section. The entries are sourced from middleware calls to `record_stream_usage(stream_name, context)` and make it easy to see which GUI actions spawned specific RNG streams.

## Accessibility and UX considerations

- **Keyboard-friendly navigation** – All tabs and primary actions are reachable via <kbd>Tab</kbd> order. Focus indicators are intentionally high-contrast to support artists who rely on keyboard navigation.
- **Legible typography** – The default theme uses a minimum 14pt UI font with adjustable scaling in **Settings > Accessibility**. Scaling applies to both labels and input controls.
- **Colour contrast** – Status badges use dual coding (colour plus iconography) so success, warning, and error states remain distinguishable for colour-blind users.
- **Error explanations** – Middleware error payloads are translated into plain language tooltips with links back to this handbook, removing the need to parse stack traces.
- **Session persistence** – The GUI remembers your last-used strategy and seed between sessions by reading and writing the same values exposed by the middleware, reducing repetitive configuration.

## Troubleshooting (plain-language answers)

| Symptom | What to try | Middleware link |
| --- | --- | --- |
| **"No strategies available" in the dropdown** | Ensure the Godot project autoloads are active (see the launch checklist) and press the **Reload Strategies** button. This re-invokes `RNGProcessor.list_strategies()` to rebuild the list. | `list_strategies()` |
| **"Failed to generate" error banner** | Double-check your inputs; required fields turn red if missing. If the error persists, open the Debug Logs tab to read the detailed message captured from `generation_failed`. | `generate(...)`, `generation_failed` |
| **Debug Logs tab is empty** | Toggle "Record DebugRNG Session" and run the generator again. The button wires up `RNGProcessor.set_debug_rng(...)` so the middleware actually writes the log file. | `set_debug_rng(...)`, `get_debug_rng()` |
| **Seed value keeps changing unexpectedly** | Confirm you did not enable "Randomize seed before each run" in the toolbar. Disable it to keep using your manually applied seed via `set_master_seed(...)`. | `set_master_seed(...)`, `reset_master_seed()` |
| **GUI window will not launch** | Open Godot's output panel for errors. Missing autoloads or a renamed project folder prevent the scene from finding `RNGProcessor`. Restore the original `project.godot` path and retry. | Autoload access |

## Where to learn more

- [`devdocs/rng_processor_manual.md`](./rng_processor_manual.md) – Deep dive into every middleware API used by the Platform GUI.
- [`name_generator/tools/README.md`](../name_generator/tools/README.md) – Command-line alternatives for batch workflows.
- [`devdocs/tooling.md`](./tooling.md) – Diagnostics runners, test manifests, and other QA utilities.

Bring unanswered questions to the #platform-artists channel so the tools team can expand this handbook.
