# Platform GUI Artist Handbook

## Purpose and scope

The Platform GUI is the artist-facing control centre for deterministic name generation. It lets art and narrative teams experiment with generator strategies, run batch jobs with predictable seeds, and inspect the same DebugRNG telemetry that support engineers rely on when triaging issues. Everything the interface does is powered by the `RNGProcessor` middleware documented in [`devdocs/rng_processor_manual.md`](./rng_processor_manual.md); this guide explains the GUI in artist-friendly language and shows how each button maps to a middleware capability.

## Launch checklist

Follow these steps whenever you need to work inside the Platform GUI. The condensed version lives in [`devdocs/platform_gui_checklists.md`](./platform_gui_checklists.md) so you can print, export, or embed it in production playbooks.

1. **Open the Godot project** – Launch Godot 4.4 and open `project.godot` from the repository root. The GUI scene tree expects the `RNGProcessor` autoload to be active, so do not create a blank project or rename the root folder.
2. **Confirm autoloads** – In the Godot editor, open **Project > Project Settings > Autoload** and verify that `RNGManager`, `NameGenerator`, and `RNGProcessor` are all enabled. These singletons are the bridges between the GUI and the middleware. If any are missing, press the refresh icon to reload project settings or re-add them by pointing to the corresponding `.gd` files in `res://autoloads/`.
3. **Run the GUI scene** – Press <kbd>F5</kbd> (or click the play icon) to launch `Main_Interface.tscn`, the default scene that wires the Platform GUI shell together. The window should appear with tabs for *Generators*, *Seeds*, *Debug Logs*, *Exports*, and *Admin Tools*.【F:project.godot†L1-L40】【F:Main_Interface.tscn†L1-L53】
4. **Optional: enable DebugRNG logging** – If you want the GUI to collect detailed telemetry, open the DebugRNG toolbar, capture the session metadata (label, ticket ID, quick notes), press **Start session**, and then click **Attach**. The toolbar wires the helper through `RNGProcessor.set_debug_rng(...)` so the middleware starts writing the session report immediately.

## Tab overview

| Tab | Purpose | Quick actions |
| --- | --- | --- |
| **Generators** | Configure, preview, and export strategy payloads. | Generate, preview, bookmark configs |
| **Seeds** | Manage master seed, stream routing, and deterministic state exports. | Apply, randomise, import/export state |
| **Debug Logs** | Inspect DebugRNG telemetry in real time. | Refresh log, filter sections, download reports |
| **Dataset Health** | Audit on-disk resources, launch the syllable builder, and follow up on dataset warnings. | Refresh inventories, open tooling, deep-link docs |
| **Formulas** | Combine hybrid and template strategies for deterministic sentences. | Preview formulas, inspect seed inheritance |
| **Exports** | Batch queued generator runs into export-ready payloads and shareable manifests. | Stage batch jobs, export CSV/JSON, attach DebugRNG snapshot |
| **Admin Tools** | Manage bookmarks, workspace layouts, feature flags, and onboarding presets. | Restore defaults, sync bookmarks, toggle experimental features |

## Common workflows

### Recording DebugRNG sessions

1. Open the DebugRNG toolbar (bundled with `res://addons/platform_gui/components/DebugToolbar.tscn`). Populate the metadata fields so support tickets, QA notes, and quick descriptors are stored alongside the session.
2. Press **Start session** to create a fresh DebugRNG helper. The toolbar caches the helper and keeps it ready for attachment without touching engine singletons.
3. Click **Attach** to route the helper through the RNGProcessor controller. The middleware now emits timeline, warning, and stream-usage telemetry directly into the recorder.
4. Use **Detach** whenever you want to pause logging without destroying the captured session. Press **Stop** to close the report, persist the TXT file, and release the helper.

### Running a generator

1. Open the **Generators** tab. The strategy dropdown is populated via `RNGProcessor.list_strategies()`, so the list always matches what the middleware advertises.
2. Select a strategy. The configuration form and helper text are fetched from `RNGProcessor.describe_strategy(id)`, ensuring the GUI validates inputs using the same schema the middleware expects.
3. Enter the desired parameters. Required fields are highlighted and include inline descriptions written for narrative teams.
4. Press **Generate**. The GUI calls `RNGProcessor.generate(config)` behind the scenes. While the middleware processes the request, the interface shows a status spinner driven by the `generation_started` signal.
5. Review the result. Successful runs display the returned payload alongside the resolved seed and RNG stream name reported by `generation_completed`. If the middleware emits `generation_failed`, the GUI surfaces the human-readable error message plus suggested fixes.

### Staging batch exports

1. Switch to the **Exports** tab. The top banner shows the active workspace profile and links to the printable checklists documented in [`devdocs/platform_gui_checklists.md`](./platform_gui_checklists.md#batch-export-readiness).
2. Press **Add job** to capture the current generator configuration. Jobs store strategy IDs, config payloads, and the seed metadata so reproducibility survives between sessions.
3. Use **Annotate** to record localisation, platform, or sprint identifiers. These annotations appear in the exported manifest and the DebugRNG snapshot bundle.
4. Choose an export format. The GUI supports CSV (flattened results) and JSON (full payloads plus metadata). CSV exports automatically expand arrays into semicolon-separated strings for spreadsheet compatibility.
5. Click **Run batch**. The GUI iterates through queued jobs, invoking `RNGProcessor.generate(...)` for each entry. Progress indicators echo the same lifecycle signals as the single-run workflow so you can monitor successes and failures in real time.
6. When the batch completes, use **Download bundle** to retrieve the manifest, raw results, and optional DebugRNG TXT snapshot in a timestamped directory. The handoff is optimised for archival and external QA submission.

### Managing bookmarks and workspace presets

1. Open the **Admin Tools** tab. This view loads user-specific workspace preferences stored under `user://platform_gui/settings.json`.
2. Use **Save current layout** to bookmark the active tab, panel sizing, and debug toolbar state. Artists can return to the layout later via **Restore layout**.
3. Toggle feature flags in the **Experimental features** list to opt in or out of beta panels. Flags are validated against the middleware’s capabilities so unsupported experiments are hidden automatically.
4. Press **Sync bookmarks** to export your presets as JSON. The file can be shared with other artists or restored during onboarding to guarantee consistent workspace defaults.

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

### Auditing dataset health

1. Switch to the **Dataset health** tab (`res://addons/platform_gui/panels/datasets/DatasetInspectorPanel.tscn`). The header button runs `dataset_inspector.gd`, captures stdout and warning output through the editor, and renders an inline folder inventory so you can triage missing assets without launching the headless tool.【F:addons/platform_gui/panels/datasets/DatasetInspectorPanel.gd†L1-L110】
2. Review the **Warnings** stack beneath the listing. Empty directories, missing roots, or other script warnings show up with ⚠️ markers and red status text so you know exactly which folders still need content before sign-off.【F:addons/platform_gui/panels/datasets/DatasetInspectorPanel.gd†L101-L144】
3. Use **Open syllable builder** when the inspection highlights syllable gaps. The button enables the Syllable Set Builder plugin and nudges artists toward the dock that converts curated word lists into `SyllableSetResource` files.【F:addons/platform_gui/panels/datasets/DatasetInspectorPanel.gd†L67-L84】【F:name_generator/tools/SyllableSetBuilder.gd†L1-L95】
4. Click **Dataset guide** or the contextual link at the bottom of the panel whenever you need sourcing and normalisation reminders while you clean up the data. The shortcut jumps straight to [`devdocs/datasets.md`](./datasets.md).【F:addons/platform_gui/panels/datasets/DatasetInspectorPanel.gd†L85-L119】

### Crafting sentence formulas

1. Open the **Formulas** workspace (`res://addons/platform_gui/workspaces/formulas/FormulasWorkspace.tscn`). The top banner links to the matching anchor inside [`devdocs/sentences.md`](./sentences.md) so you can cross-reference the original blueprint while you work.
2. Choose a blueprint from the selector. Each option pre-loads the HybridStrategy steps and the nested TemplateStrategy used in the handbook example. The inline notes recap which datasets are involved and why the seeds use specific prefixes.
3. Review the **Seed & Alias Propagation** panel. Rows tinted blue confirm that aliases inherit the pipeline seed (for example, `skill_sentence_v1::step_skill_verb`), while red rows highlight missing aliases or seeds that need attention before previews stay deterministic.
4. Edit the template node in the right column. Any changes automatically sync into the matching hybrid step so the in-panel template editor and the standalone template workspace always reflect the same configuration.
5. Press **Preview formula** to run the combined payload through the middleware. Successful runs return a single deterministic sentence, and the seed tree updates with the latest inheritance trail so you can export the configuration knowing exactly which RNG streams were used.

### Reviewing DebugRNG logs

1. Switch to the **Debug Logs** tab. When DebugRNG is active, the middleware writes to `user://debug_rng_report.txt` (or a custom path you configured earlier).
2. Click **Refresh log**. This button requests the latest telemetry via `RNGProcessor.get_debug_rng().read_current_log()` and updates the viewer pane without reparsing the TXT output.
3. Use the section filter dropdown to jump between **Generation timeline**, **Warnings**, **Stream usage**, and **Strategy errors**. Highlighted entries mirror the telemetry schema—warnings render with the ⚠️ glyph while failures and strategy errors are tinted red—so analysts can scan for issues in seconds.
4. Enter a target file (for example `user://debug_rng_copy.txt`) and press **Download** to archive the latest TXT report. The panel streams the raw file directly to disk so engineers can attach it to tickets or share it with QA leads.

### Replaying and exporting seeds

1. Navigate to the **Seeds** tab to load the Seeds Dashboard panel. The header calls `RNGProcessorController.get_master_seed()` so the displayed value always mirrors the middleware, even when the window has been idle.
2. To replay a previous session, paste the recorded seed into **Enter master seed** and press **Apply**. The dashboard forwards the value to `RNGProcessor.initialize_master_seed(...)`, emitting a confirmation banner and refreshing the derived stream list.
3. Need a brand-new deterministic branch? Click **Randomize**. The panel calls `RNGProcessor.randomize_master_seed()` and drops the result into the input field so you can store it alongside captured screenshots or logs.
4. Review the **Derived RNG streams** table. Rows are populated from `RNGProcessor.describe_rng_streams()` and show both the seed/state tuple and whether the data originated from the live `RNGManager` singleton or the middleware's fallback cache.
5. Inspect the **Stream routing preview** when you need to explain how branches are derived. The panel renders `RNGProcessor.describe_stream_routing()` output so support engineers can point to the `rng_processor::stream_name` path used by `RNGStreamRouter` whenever `RNGManager` is offline.
6. Use **Export state** to copy the current topology to the clipboard. The control proxies `RNGProcessor.export_rng_state()`, pretty-prints the JSON in the text area, and keeps the payload ready for version control or bug reports.
7. When recreating an issue, paste a previously exported payload and press **Import state**. The panel validates the JSON before calling `RNGProcessor.import_rng_state(...)`, restoring the master seed plus every captured stream position.
8. For cross-checks while debugging, jump to the Debug Logs tab and read the Stream Usage section written by `record_stream_usage(stream_name, context)`. Entries mirror the same stream identifiers listed in the dashboard so analysts can trace GUI actions back to RNG derivations.

### Publishing export bundles

1. After collecting deterministic samples in the **Exports** tab, press **Open bundle location** to reveal the export directory in your file browser.
2. Validate that the CSV/JSON files are accompanied by the DebugRNG TXT snapshot and the summary README. Use the [Batch export readiness checklist](./platform_gui_checklists.md#batch-export-readiness) to confirm everything is properly labelled.
3. Zip the folder (or drag it into your studio’s asset handoff template) so the manifest, sample payloads, and seeds remain coupled.
4. Attach the bundle to the tracking ticket. QA can import the `rng_state.json` file through the Seeds tab to replay the run with identical seeds.

### Deterministic QA workflow

1. Use **Export state** in the Seeds Dashboard to capture the master seed and active stream positions before committing reproductions.
2. Attach the exported JSON to your test plan (or paste it into a fixture) so anyone can hydrate the same topology via **Import state**.
3. Re-run the automated suites with:
   ```bash
   godot --headless --script res://tests/run_generator_tests.gd
   godot --headless --script res://tests/run_platform_gui_tests.gd
   godot --headless --script res://tests/run_diagnostics_tests.gd
   ```
   The Platform GUI run covers controller integrations and the `Main_Interface` scene test, while the generator and diagnostics runs confirm the middleware still produces deterministic results after the restart.【F:tests/run_generator_tests.gd†L1-L36】【F:tests/run_platform_gui_tests.gd†L1-L36】【F:tests/run_diagnostics_tests.gd†L1-L36】【F:tests/interface/test_main_interface_scene.gd†L1-L170】

## Accessibility and UX considerations

- **Keyboard-friendly navigation** – All tabs and primary actions are reachable via <kbd>Tab</kbd> order. Focus indicators are intentionally high-contrast and animate with motion-reduced styles when **Settings > Accessibility > Reduce Motion** is enabled.
- **Screen reader support** – Landmark regions label each primary tab, and all actionable buttons expose descriptive `accessible_description` strings that mirror the terminology in this handbook. Seed values are announced in groups so screen reader users hear the prefix, stream, and numeric seed without confusion.
- **Legible typography** – The default theme uses a minimum 14pt UI font with adjustable scaling in **Settings > Accessibility**. Scaling applies to labels, inputs, status badges, and the Debug Logs viewer.
- **Colour contrast** – Status badges use dual coding (colour plus iconography) so success, warning, and error states remain distinguishable for colour-blind users. High-contrast mode replaces subtle status colours with textured backgrounds for additional differentiation.
- **Error explanations** – Middleware error payloads are translated into plain language tooltips with links back to this handbook, removing the need to parse stack traces.
- **Session persistence** – The GUI remembers your last-used strategy, seed, export preset, and Admin Tools flags between sessions by reading and writing the same values exposed by the middleware, reducing repetitive configuration.
- **Input safeguards** – Numeric fields clamp to middleware-supported ranges, and sliders include optional text entry for artists who cannot comfortably use drag gestures.

## Troubleshooting (plain-language answers)

| Symptom | What to try | Middleware link |
| --- | --- | --- |
| **"No strategies available" in the dropdown** | Ensure the Godot project autoloads are active (see the launch checklist) and press the **Reload Strategies** button. This re-invokes `RNGProcessor.list_strategies()` to rebuild the list. | `list_strategies()` |
| **Generator previews ignore the selected seed** | Verify that **Randomize seed before each run** is disabled and that the Seeds tab shows the seed you expect. If the Admin Tools flag **Force random seeds** is on, turn it off to respect manual seeds. | `set_master_seed(...)`, `randomize_master_seed()` |
| **"Failed to generate" error banner** | Double-check your inputs; required fields turn red if missing. If the error persists, open the Debug Logs tab to read the detailed message captured from `generation_failed`. Use **Copy config JSON** to share the failing payload with engineers. The inline hint links to the relevant table below for strategy-specific fixes. | `generate(...)`, `generation_failed` |
| **Debug Logs tab is empty** | Toggle "Record DebugRNG Session" and run the generator again. The button wires up `RNGProcessor.set_debug_rng(...)` so the middleware actually writes the log file. | `set_debug_rng(...)`, `get_debug_rng()` |
| **Export bundle missing DebugRNG snapshot** | Confirm **Include DebugRNG snapshot** is enabled before running **Run batch** in the Exports tab. If the toggle is missing, open Admin Tools and enable the **Exports.DebugRNG** feature flag. | `set_debug_rng(...)`, `get_debug_rng()` |
| **Seed value keeps changing unexpectedly** | Confirm you did not enable "Randomize seed before each run" in the toolbar. Disable it to keep using your manually applied seed via `set_master_seed(...)`. | `set_master_seed(...)`, `reset_master_seed()` |
| **Admin Tools flags do not persist** | Check file permissions for `user://platform_gui/settings.json`. If Godot cannot write to that file, presets revert to defaults. Delete the file to regenerate it after fixing permissions. | Settings persistence |
| **GUI window will not launch** | Open Godot's output panel for errors. Missing autoloads or a renamed project folder prevent the scene from finding `RNGProcessor`. Restore the original `project.godot` path and retry. | Autoload access |

### Middleware error quick reference

When the middleware reports an error, the GUI now shows a plain-language summary, a remediation checklist, and a direct reference to the handbook. Use the tables below to dig deeper into each family of errors. Every row mirrors the hint/tooltip structure surfaced in the panels.

#### Configuration payloads {#middleware-errors-configuration}

| Error code | What it means | How to fix it |
| --- | --- | --- |
| `invalid_config_type` | Configuration payload must be provided as a Dictionary. | Regenerate the payload from the GUI form or rebuild it using the handbook configuration template. |

#### Required key mismatches {#middleware-errors-required-keys}

| Error code | What it means | How to fix it |
| --- | --- | --- |
| `missing_required_keys` | Configuration is missing at least one required key. | Compare your payload with the required key list documented in this handbook before retrying. |

#### Optional key typing {#middleware-errors-optional-types}

| Error code | What it means | How to fix it |
| --- | --- | --- |
| `invalid_key_type` | Optional key value does not match the expected type. | Confirm each optional key uses the type shown in the optional key reference table. |

#### Resource lookups {#middleware-errors-resources}

| Error code | What it means | How to fix it |
| --- | --- | --- |
| `missing_resource` | Referenced resource could not be loaded from disk. | Verify the path, file extension, and import status against the resource checklist. |
| `invalid_resource_type` | Loaded resource exists but does not match the expected type. | Open the referenced file in Godot and confirm it inherits from the required resource class. |

#### Word list datasets {#middleware-errors-wordlists}

| Error code | What it means | How to fix it |
| --- | --- | --- |
| `invalid_wordlist_paths_type` | `wordlist_paths` must contain resource paths or `WordListResource` instances. | Select word lists through the GUI picker or mirror the array structure described in the handbook. |
| `invalid_wordlist_entry` | Word list entries must be strings or `WordListResource` objects. | Clean the array so only resource paths or preloaded resources remain before generating. |
| `wordlists_missing` | No word list resources were provided to the strategy. | Use the resource browser to add at least one dataset before generating. |
| `wordlists_no_selection` | The configured word lists did not return any entries. | Double-check that each word list contains entries and the filters match the handbook workflow. |
| `wordlist_invalid_type` | Loaded resource is not a `WordListResource`. | Confirm the path targets a `.tres` exported from the word list builder tools. |
| `wordlist_empty` | Word list resource does not expose any entries. | Populate the dataset via the builder and reimport before attempting another preview. |

#### Syllable chain ranges {#middleware-errors-syllable-ranges}

| Error code | What it means | How to fix it |
| --- | --- | --- |
| `invalid_syllable_set_path` | `syllable_set_path` must be a valid resource path. | Browse to an existing syllable set asset listed in the handbook inventory. |
| `invalid_syllable_set_type` | Loaded resource is not a `SyllableSetResource`. | Rebuild the asset using the syllable set builder described in the handbook. |
| `empty_prefixes` | Selected syllable set is missing prefix entries. | Edit the dataset so every required syllable column contains at least one entry. |
| `empty_suffixes` | Selected syllable set is missing suffix entries. | Populate suffix data in the resource before generating again. |
| `missing_required_middles` | Configuration requires middle syllables but the resource has none. | Add middle syllables to the dataset or disable the `require_middle` option. |
| `middle_syllables_not_available` | Requested middle syllables but the resource does not define any. | Reduce the middle syllable range or update the dataset with middle entries. |
| `invalid_middle_range` | `middle_syllables` must define a valid min/max range. | Ensure min is less than or equal to max and matches the examples in the handbook. |
| `unable_to_satisfy_min_length` | Generated name could not reach the requested minimum length. | Lower the minimum length or expand the syllable set to include longer fragments. |

#### Template nesting {#middleware-errors-template-nesting}

| Error code | What it means | How to fix it |
| --- | --- | --- |
| `invalid_template_type` | Template payload must be a string before tokens can be resolved. | Copy the template examples directly from the handbook to restore the correct syntax. |
| `empty_token` | Template contains an empty token placeholder. | Replace empty placeholders with named tokens so they can map to sub-generators. |
| `missing_template_token` | Template references a token that is not defined in `sub_generators`. | Add a matching entry to the sub-generator dictionary following the handbook example. |
| `invalid_sub_generators_type` | `sub_generators` must be a Dictionary keyed by template tokens. | Restructure the payload so each token maps to a configuration dictionary. |
| `invalid_max_depth` | `max_depth` must be a positive integer. | Set `max_depth` using the defensive defaults outlined in the handbook. |
| `missing_strategy` | Sub-generator entry is missing its `strategy` identifier. | Assign a strategy ID that matches the middleware catalog before generating. |
| `template_recursion_depth_exceeded` | Nested templates exceeded the configured `max_depth`. | Increase `max_depth` or simplify nested calls per the handbook escalation steps. |
| `invalid_name_generator_resource` | Fallback `NameGenerator` resource is not a valid GDScript. | Point the configuration to the bundled script path listed in the handbook. |
| `name_generator_unavailable` | `NameGenerator` singleton or script is unavailable. | Enable the autoloads noted in the launch checklist or restore the default script path. |

#### Hybrid pipelines {#middleware-errors-hybrid-pipelines}

| Error code | What it means | How to fix it |
| --- | --- | --- |
| `invalid_steps_type` | Hybrid strategy expects `steps` to be an Array of dictionaries. | Collect step definitions through the Hybrid panel so the payload structure matches the handbook. |
| `empty_steps` | Hybrid strategy requires at least one configured step. | Add a step that points to a generator or reuse the starter pipelines documented in the handbook. |
| `invalid_step_entry` | Each hybrid step must be a Dictionary entry. | Recreate the step via the GUI to avoid mixing scalar values with configuration dictionaries. |
| `invalid_step_config` | Hybrid step `config` payload must be a Dictionary. | Open the child panel referenced in the handbook to capture a fresh configuration block. |
| `missing_step_strategy` | Hybrid step is missing its `strategy` identifier. | Select a generator for every step so the middleware knows which strategy to invoke. |
| `hybrid_step_error` | A nested hybrid step reported its own error. | Inspect the step details and open the referenced panel for targeted troubleshooting. |

#### Markov chain datasets {#middleware-errors-markov-models}

| Error code | What it means | How to fix it |
| --- | --- | --- |
| `invalid_markov_model_path` | `markov_model_path` must point to a `MarkovModelResource`. | Select a model from the Dataset Health inventory before requesting a preview. |
| `missing_markov_model_path` | Configuration omitted the Markov model path. | Fill in the model path or pick a dataset using the Markov panel workflow. |
| `invalid_model_states` | Markov model state table is malformed. | Re-export the dataset using the builder to refresh state counts. |
| `invalid_model_start_tokens` | Start token array contains invalid data. | Verify the start token definitions following the Markov checklist. |
| `invalid_model_end_tokens` | End token array contains invalid data. | Review the termination tokens described in the handbook and update the resource. |
| `invalid_transitions_type` | Transition table must be a Dictionary keyed by token. | Regenerate the model to ensure transitions use the documented schema. |
| `empty_transition_block` | Transition table contains an empty block. | Populate every transition bucket or remove unused tokens before exporting. |
| `invalid_transition_block` | Transition block does not match the expected array layout. | Restore the weight/value pairs illustrated in the handbook transition examples. |
| `invalid_transition_entry_type` | Transition entries must be Dictionaries describing token/weight pairs. | Rebuild the transitions using the Markov editor workflow. |
| `invalid_transition_token_type` | Transition entry token must be a String. | Review the dataset export script and ensure tokens are serialised as text. |
| `invalid_transition_weight_type` | Transition weight must be numeric. | Normalise weight values to floats or integers before exporting the model. |
| `invalid_transition_weight_value` | Transition weight must be greater than zero. | Remove negative or zero weights so sampling behaves predictably. |
| `non_positive_weight_sum` | Transition weights sum to zero or less. | Rebalance the weights so they sum to a positive value as shown in the handbook. |
| `missing_transition_token` | A transition entry is missing its token value. | Add the token string or delete the incomplete entry before exporting. |
| `missing_transition_for_token` | Model lacks a transition table for one of the referenced tokens. | Regenerate the dataset to include transitions for every token referenced in the state table. |
| `unknown_token_reference` | Transition references a token that is not defined in the model. | Cross-check the token inventory and remove stale references. |
| `invalid_token_temperature_type` | Temperature overrides must be numeric. | Set token temperatures to floats as demonstrated in the handbook examples. |
| `invalid_token_temperature_value` | Token temperature must be greater than zero. | Use positive values when adjusting token temperature overrides. |
| `invalid_transition_temperature_type` | Transition temperature overrides must be numeric. | Ensure transition overrides mirror the numeric structure from the handbook. |
| `invalid_transition_temperature_value` | Transition temperature must be greater than zero. | Audit override values and keep them positive as shown in the troubleshooting guide. |
| `invalid_default_temperature` | Default temperature must be numeric and above zero. | Update the config to use the safe defaults captured in the handbook. |
| `invalid_max_length_type` | `max_length` must be an integer. | Provide numeric values when clamping generated token counts. |
| `invalid_max_length_value` | `max_length` must be greater than zero. | Use the minimum thresholds suggested in the handbook before sampling. |
| `max_length_exceeded` | Generation stopped after exceeding the configured `max_length`. | Increase `max_length` or relax temperature constraints per the troubleshooting table. |

## Engineering implementation notes

This section is designed for engineers extending or maintaining the Platform GUI. Artists can skip ahead to the resource links.

### Code structure

- **Primary entry points** – The GUI scene lives in `res://addons/platform_gui/PlatformGui.tscn`. Each tab is a dedicated panel script that emits signals consumed by `PlatformGuiController.gd`.
- **Middleware integration** – All middleware calls are routed through `RNGProcessorController.gd` to keep UI layers testable. Avoid calling `RNGProcessor` directly from panel scripts unless the controller explicitly exposes the helper you need.
- **Signals and telemetry** – When adding new actions, emit `generation_started`, `generation_completed`, or `generation_failed` signals through the controller so DebugRNG timelines remain accurate.
- **Feature flags** – Admin Tools uses a lightweight feature flag service backed by `user://platform_gui/settings.json`. Add new flags here when shipping beta panels so QA can opt in without affecting everyone.

### Development workflow

1. **Scene isolation** – Launch panels in isolation by right-clicking their `.tscn` files and choosing **Open Scene**. The panel scripts stub middleware calls when the controller is absent, making it easier to iterate on UI while backend code evolves.
2. **Unit tests** – Extend the existing Godot test harness with panel-specific scripts under `tests/gui/`. Tests should load the scene, inject a fake `RNGProcessorController`, and assert that signals and validation states change as expected.
3. **DebugRNG integration** – When adding new workflows, update the DebugRNG toolbar annotations so exported bundles contain helpful context. Engineers should wire new panel actions into the telemetry stream before code review.
4. **Documentation sync** – Any new tab or workflow must be reflected in this handbook and the printable checklists. Run `rg` for the tab name to ensure references stay in sync.

### Performance guidelines

- Batch exports stream results one job at a time; avoid blocking the UI thread with synchronous file writes. Use deferred calls or background threads when generating large bundles.
- Keep dataset inventory scans within a worker so the Dataset Health tab stays responsive. Cache results and expose a manual refresh button instead of constant polling.
- When integrating new middleware APIs, wrap them in throttled calls (e.g., only refresh Debug Logs when the window is visible) to reduce pressure on headless automation.

## Where to learn more

- [`devdocs/rng_processor_manual.md`](./rng_processor_manual.md) – Deep dive into every middleware API used by the Platform GUI.
- [`name_generator/tools/README.md`](../name_generator/tools/README.md) – Command-line alternatives for batch workflows.
- [`devdocs/tooling.md`](./tooling.md) – Diagnostics runners, test manifests, and other QA utilities.

Bring unanswered questions to the #platform-artists channel so the tools team can expand this handbook.
