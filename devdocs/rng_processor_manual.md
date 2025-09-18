# RNGProcessor Middleware Manual

## Overview

`RNGProcessor` is the deterministic middleware that bridges gameplay systems and the `NameGenerator` / `RNGManager` singletons. It ships as a Godot autoload (see `project.godot`) so editor tools, tests, and runtime code can rely on a stable API surface without managing node lifecycles. The processor

- normalises seed handling across every request,
- shields callers from direct dependencies on `NameGenerator` internals,
- emits structured signals that analytics dashboards and the forthcoming Platform GUI can observe, and
- exposes hooks for attaching the `DebugRNG` telemetry helper.

The class lives at `res://name_generator/RNGProcessor.gd` and can be retrieved anywhere in project code through `Engine.get_singleton("RNGProcessor")` or the global shorthand `RNGProcessor`.

## Core responsibilities

1. **Seed governance** – `RNGProcessor` forwards seed mutations to `RNGManager` when available and maintains lightweight fallbacks for isolated tests. This ensures a single source of truth for the master seed regardless of the execution environment.
2. **Request brokering** – All `NameGenerator.generate(...)` calls can be routed through the processor. It performs defensive checks, forwards successful invocations, and surfaces structured errors when the generator singleton is unavailable.
3. **Observability & telemetry** – The middleware emits start/finish/failure signals and, when paired with `DebugRNG`, records RNG stream derivations. These guarantees are what the Platform GUI will rely on to render live job timelines and replay previous sessions deterministically.

## Public API quick reference

### Seed control

- `initialize_master_seed(seed_value: int)` / `set_master_seed(seed_value: int)` – Apply an explicit session seed and flush any cached fallback streams.
- `randomize_master_seed() -> int` – Generate a fresh seed via `RandomNumberGenerator`, broadcast it to `RNGManager`, and return the value so callers can persist it.
- `reset_master_seed() -> int` – Alias that randomises and returns the new seed; helpful for UI buttons that need to display the updated value immediately.
- `get_master_seed() -> int` – Query the currently active master seed (falls back to the processor’s cached copy when `RNGManager` is not registered, e.g. during headless unit tests).
- `get_rng(stream_name: String) -> RandomNumberGenerator` – Request a deterministic stream. When `RNGManager` is present the call is proxied; otherwise a hashed fallback stream derived from the current master seed is served.
- `describe_rng_streams() -> Dictionary` – Return a snapshot of the master seed plus every known RNG stream. When `RNGManager` is online the dictionary mirrors `RNGManager.save_state()`. In fallback mode it exposes the middleware’s cached streams together with their router paths so tooling can visualise derivations.
- `describe_stream_routing(stream_names := PackedStringArray()) -> Dictionary` – Build a deterministic routing preview by hashing the supplied stream names (or every observed stream when left empty) with `RNGStreamRouter`. The payload includes the resolved seeds and human-readable notes describing whether the data came from `RNGManager` or the fallback cache.
- `export_rng_state() -> Dictionary` / `import_rng_state(payload: Variant)` – Persist and restore the entire RNG topology. These calls round-trip `RNGManager.save_state()` / `load_state()` when the singleton is present and fall back to the middleware’s cache when running in isolation.

### Request execution & strategy metadata

- `list_strategies() -> PackedStringArray` – Enumerate the registered generator strategies without touching the `NameGenerator` internals. The Platform GUI uses this call to populate dropdowns dynamically.
- `describe_strategy(id: String) -> Dictionary` and `describe_strategies() -> Dictionary` – Fetch per-strategy metadata, including expected configuration schemas, for tooling validation layers.
- `generate(config: Variant, override_rng: RandomNumberGenerator = null) -> Variant` – Execute a generation request through `NameGenerator`. The processor emits lifecycle signals (described below) and mirrors any error payloads from the generator, making it safe for UI code to inspect failure codes without digging into strategy implementations.

### Signals & observability hooks

- `generation_started(request_config, metadata)` – Fired before delegating to `NameGenerator`. `metadata` includes the resolved strategy identifier, seed (when provided), and RNG stream name.
- `generation_completed(request_config, result, metadata)` – Fired after a successful run. `result` is the raw payload returned by the active strategy.
- `generation_failed(request_config, error, metadata)` – Fired when the generator is missing or a strategy reports a structured error. The signal payload mirrors the dictionary returned by `NameGenerator.generate`.
- `set_debug_rng(debug_rng: DebugRNG, attach_to_debug := true)` / `get_debug_rng()` – Attach or inspect a `DebugRNG` observer. When `attach_to_debug` is `true`, the helper automatically begins monitoring lifecycle signals and propagates itself to `NameGenerator` so strategy-level events are also captured.

These surface areas are what the Platform GUI will observe. By listening to the signals, the UI can show per-request timelines, associate results with RNG stream derivations, and offer “re-run with same seed” affordances without needing private knowledge of the name generator.

## DebugRNG integration and log reference

`DebugRNG` (located at `res://name_generator/tools/DebugRNG.gd`) serialises a human-readable TXT report after each session. Attach it to the processor with:

```gdscript
var debug_rng := DebugRNG.new()
debug_rng.begin_session({"suite": "platform_smoke"})
debug_rng.attach_to_processor(RNGProcessor, "user://debug_rng_report.txt")
```

### Default location and configuration knobs

- **Default path** – `DebugRNG.DEFAULT_LOG_PATH` resolves to `user://debug_rng_report.txt`. Pass a custom path to `attach_to_processor(processor, log_path)` to redirect the output. The helper remembers the last non-empty path you supplied.
- **Session metadata** – Call `begin_session(metadata := {})` before triggering jobs to record build identifiers, platform details, or scenario names in the report’s header.
- **Lifecycle management** – Invoke `close()` (or the alias `dispose()`) when you are done to flush the accumulated log to disk. When attached through `RNGProcessor.set_debug_rng(...)`, closing is handled automatically once the helper is disposed by tooling code.
- **Stream tracking** – The processor forwards stream derivations through `record_stream_usage(stream_name, context)` so you can map every derived RNG stream back to the original request.

### TXT report layout

When `close()` executes, DebugRNG writes a structured plaintext document with the following sections:

1. **Header** – Title plus blank separator line.
2. **Session Metadata** – Start/end timestamps followed by any key/value pairs passed into `begin_session`.
3. **Generation Timeline** – Ordered entries (`START`, `COMPLETE`, `FAIL`, `STRATEGY_ERROR`) that chronicle each middleware signal, including timestamps, strategy identifiers, seeds, stream names, and either results or error codes.
4. **Warnings** – Optional bullet list populated through `record_warning(message, context)`.
5. **Stream Usage** – Bullet list enumerating each RNG stream recorded along with contextual metadata (strategy, seed, and whether the stream came from a config override or derived fallback).
6. **Aggregate Statistics** – Totals for started/completed/failed calls, strategy errors, warnings, and stream records.

Support engineers investigating issues should grab the latest `user://debug_rng_report.txt` (or whatever path their tooling configured) from the affected machine and attach it to bug reports. The Platform GUI will offer a “Download DebugRNG log” button that simply copies this file.

## Relationship to the Platform GUI

The planned Platform GUI is effectively a front-end that consumes the middleware API documented above. It will:

- use `list_strategies()` / `describe_strategies()` to populate configuration forms,
- call `generate(...)` with the requested seed and stream overrides,
- subscribe to the lifecycle signals to animate status indicators, and
- display DebugRNG session metadata and stream usage summaries inside its troubleshooting panel.

Because the middleware already decouples callers from `NameGenerator` internals, the GUI (and any other client) can evolve independently while keeping compatibility guarantees: as long as the documented API surface remains stable, existing automation and tooling will continue to function without modification.
