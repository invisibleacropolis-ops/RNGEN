# RNGProcessor Field Guide

This guide is aimed at engineers who are integrating the name generation stack into gameplay or external tooling. It assumes you are familiar with Godot’s autoload system and the deterministic architecture described in `DevDoc.txt`.

## 1. Initialising the processor in-game

1. Confirm that `project.godot` lists `RNGManager`, `NameGenerator`, and `RNGProcessor` in the `[autoload]` section. The repository ships with this configuration, so most teams only need to ensure they do not remove it from custom builds.
2. During your game’s bootstrap sequence, seed the middleware once:
   ```gdscript
   var master_seed := RNGProcessor.randomize_master_seed()
   DebugPrint.info("Master seed", master_seed)
   ```
   Alternatively, set a reproducible seed retrieved from a save file with `RNGProcessor.set_master_seed(saved_seed)`.
3. When you need a name, call `RNGProcessor.generate(config_dictionary)`. The middleware handles RNG stream derivation and signal emission automatically.

If you instantiate `RNGProcessor` manually (e.g., inside an isolated test scene), call `add_child(RNGProcessor.new())` early in your scene tree and invoke `_ready()` or `initialize_master_seed(...)` before dispatching requests. The autoload setup already covers this for the main project.

## 2. Registering custom strategies

1. Create a script that extends `GeneratorStrategy` (see `devdocs/strategies.md` for scaffolding tips).
2. Register the strategy during startup by calling `NameGenerator.register_strategy("your_id", YourStrategy.new())`. `RNGProcessor.list_strategies()` immediately reflects the new entry; the middleware simply proxies the generator’s registry.
3. If you attach `DebugRNG`, the processor automatically instructs the generator to track your strategy, so `generation_error` signals will appear in the TXT logs when your code returns failures.
4. Update your client code or data definitions to supply the new `strategy` identifier inside the configuration dictionaries passed to `RNGProcessor.generate`.

## 3. Running the headless test suite

The repository bundles regression coverage for the middleware and related components. Run the suite from the project root:

```bash
godot --headless --script res://tests/run_all_tests.gd
```

This exercises both the in-engine tests (`name_generator/tests/*.gd`) and any headless scenarios (`tests/test_rng_processor_headless.gd`) that rely on the middleware. Attach the `DebugRNG` helper during new tests if you need additional telemetry—the suite already records warnings so logs stay informative.

## 4. Collecting DebugRNG logs

1. Instantiate and attach the helper:
   ```gdscript
   var debug_rng := DebugRNG.new()
   debug_rng.begin_session({
       "build": ProjectSettings.get_setting("application/config/version"),
       "scenario": "qa_smoke"
   })
   debug_rng.attach_to_processor(RNGProcessor)
   ```
2. Execute the scenarios you need to trace. Every `generation_started`, `generation_completed`, and `generation_failed` signal will appear in the timeline section.
3. When finished, call `debug_rng.close()` (or `debug_rng.dispose()`). The report is written to `user://debug_rng_report.txt` unless you passed a custom path to `attach_to_processor`.
4. Zip and share the TXT file with support or attach it to bug reports. The layout is documented in `docs/rng_processor_manual.md`.

## 5. Troubleshooting checklist

- **Missing names** – Confirm `NameGenerator` is present by checking the error dictionaries emitted via `generation_failed`. A `missing_name_generator` code indicates the autoload was removed.
- **Unexpected randomness** – Inspect the “Stream Usage” section in the DebugRNG log. It shows whether custom `rng_stream` overrides or auto-derived streams drove a request.
- **Custom strategy silent failures** – Ensure your strategy emits `generation_error` signals via `GeneratorStrategy._report_error`. DebugRNG listens for them and exposes counts in the “Aggregate Statistics” section.

For a comprehensive API reference, jump to `docs/rng_processor_manual.md`.
