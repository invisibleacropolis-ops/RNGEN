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

### Configuring Markov chain strategies

1. Choose **Markov Chain** from the strategy dropdown to load the dedicated panel.
2. Review the metadata banner and inline notes sourced from the middleware schema. The panel mirrors the required `markov_model_path` key plus optional settings like `max_length` so you know which controls unlock previews.【F:addons/platform_gui/panels/markov/MarkovPanel.gd†L44-L110】
3. Browse available `MarkovModelResource` assets in the resource list. Each entry surfaces locale and domain metadata in the label and tooltip so you can pick the right corpus without guessing.【F:addons/platform_gui/panels/markov/MarkovPanel.gd†L112-L186】
4. Select a resource to populate the summary cards. The top summary reports state counts, start/end tokens, and temperature override ranges; the health block highlights missing transitions, unreachable tokens, and direct terminators so you can gauge dataset integrity at a glance.【F:addons/platform_gui/panels/markov/MarkovPanel.gd†L188-L352】
5. Adjust **Maximum length** when you want the middleware to stop sampling once a name reaches a specific token count. Leave it at `0` to accept the natural termination point determined by the Markov model.【F:addons/platform_gui/panels/markov/MarkovPanel.gd†L52-L87】
6. Supply an optional seed label and press **Preview**. The panel forwards the seed, model path, and max length directly to `RNGProcessor.generate(...)` so you get deterministic samples. If the middleware rejects the request, the red validation stack shows the error message plus a bullet list of diagnostic details extracted from the payload.【F:addons/platform_gui/panels/markov/MarkovPanel.gd†L89-L145】【F:addons/platform_gui/panels/markov/MarkovPanel.gd†L354-L415】
7. Hit **Refresh** whenever you add new Markov models or update middleware notes—the button reloads both the schema hints and the on-disk resource catalogue.【F:addons/platform_gui/panels/markov/MarkovPanel.gd†L33-L76】【F:addons/platform_gui/panels/markov/MarkovPanel.gd†L112-L152】

### Configuring syllable chain strategies

1. Choose **Syllable Chain** from the strategy dropdown to load the dedicated panel.
2. Review the metadata banner and inline notes. They come directly from `describe_strategies()` so the panel mirrors the same schema the middleware validates against.
3. Use the resource browser to pick a `SyllableSetResource`. Each entry summarises prefix/middle/suffix counts plus locale and domain tags so you can immediately judge coverage.
4. Check the details panel beneath the list to confirm whether the resource allows empty middles. The panel automatically expands the middle syllable slider range to match the asset so you are never capped prematurely.
5. Toggle **Require at least one middle syllable** to enforce bridge syllables. When enabled the panel clamps the minimum slider to 1 so the config cannot drift below what the middleware expects.
6. Adjust the **Middle syllable range** sliders to control optional middles. Invalid ranges surface an inline validation message and the sliders tint red until corrected, matching the middleware error codes for quick debugging.
7. Set a **Minimum length** if you want the strategy to append extra middles until the generated name crosses a threshold. Leave it at `0` to accept any length.
8. Enable one or more **Regex cleanup presets** to strip stray punctuation or collapse awkward repeats after generation. The presets map to the `post_processing_rules` array in the strategy config so the middleware receives ready-to-run instructions.
9. Supply an optional seed, then click **Preview**. Successful runs render seeded output inline. Middleware validation errors are echoed in red along with human-friendly hints from the metadata service (e.g., missing resources or invalid middle ranges) so you can course-correct immediately.
10. Use **Refresh** whenever you add new syllable sets or need the latest schema hints; the button re-queries both the metadata service and the on-disk resource catalogue.

### Configuring template strategies

1. Choose **Template** from the strategy dropdown to load the dedicated panel.
2. Scan the metadata banner and helper notes sourced from `describe_strategies()`. They recap the required keys (`template_string`, `sub_generators`) and optional settings (`max_depth`, `seed`) so you can line up the config with middleware expectations.
3. Enter your template in the **Template string** field. Tokens wrapped in brackets (e.g. `[material]`) immediately appear in the token tree below so you can confirm the parser understands the structure.
4. Define child generators in the **Child generator definitions** JSON editor. Each entry should mirror a `NameGenerator.generate` payload. The panel validates the JSON as you type and highlights any tokens that do not have a matching sub-generator configuration.
5. Adjust **Max depth** when you need deeper recursion than the default `8`. The live validator mirrors TemplateStrategy's `template_recursion_depth_exceeded` guard, tinting the control red and surfacing the middleware's fix-it hint when the tree would breach the limit.
6. Supply an optional seed label; the **Seed helper** banner illustrates the derived seed path (`parent::token::occurrence`) and pulls the latest middleware seed/stream from `RNGProcessorController.get_latest_generation_metadata()` for extra context.
7. Review the **Token expansion preview** tree. Each row lists the recursion depth, resolved strategy display name, and the seed that TemplateStrategy will pass to the child generator. Nested template configs expand inline so you can verify cascaded definitions without leaving the panel.
8. Press **Preview** to request a deterministic sample. Middleware validation errors reuse the metadata service's guidance (for example, empty tokens or missing strategy keys) so the fix is always spelled out next to the relevant control.

### Crafting sentence formulas

1. Open the **Formulas** workspace (`res://addons/platform_gui/workspaces/formulas/FormulasWorkspace.tscn`). The top banner links to the matching anchor inside [`devdocs/sentences.md`](./sentences.md) so you can cross-reference the original blueprint while you work.
2. Choose a blueprint from the selector. Each option pre-loads the HybridStrategy steps and the nested TemplateStrategy used in the handbook example. The inline notes recap which datasets are involved and why the seeds use specific prefixes.
3. Review the **Seed & Alias Propagation** panel. Rows tinted blue confirm that aliases inherit the pipeline seed (for example, `skill_sentence_v1::step_skill_verb`), while red rows highlight missing aliases or seeds that need attention before previews stay deterministic.
4. Edit the template node in the right column. Any changes automatically sync into the matching hybrid step so the in-panel template editor and the standalone template workspace always reflect the same configuration.
5. Press **Preview formula** to run the combined payload through the middleware. Successful runs return a single deterministic sentence, and the seed tree updates with the latest inheritance trail so you can export the configuration knowing exactly which RNG streams were used.

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
