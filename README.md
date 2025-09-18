# RNGEN Documentation Hub

This repository hosts the Godot 4.4 project that powers the deterministic name generation stack. The runtime is organised around three autoloaded singletons:

- `RNGManager` – Governs the master seed and hands out isolated `RandomNumberGenerator` streams.
- `NameGenerator` – Provides the extensible strategy façade for gameplay and tools.
- `RNGProcessor` – Middleware that coordinates requests, surfaces telemetry, and underpins forthcoming platform UI features.

## Documentation map

| Audience | Start here | Highlights |
| --- | --- | --- |
| System designers | `DevDoc.txt` | Architectural rationale, deterministic design patterns, strategy deep dives. |
| Integrators & tool engineers | `docs/rng_processor_manual.md` | Middleware responsibilities, API/signal reference, DebugRNG log format, Platform GUI context. |
| Artists & narrative leads | `devdocs/platform_gui_handbook.md` | Platform GUI overview, step-by-step workflows, seed replaying, DebugRNG review tips, accessibility guidance. |
| Gameplay programmers | `devdocs/rng_processor.md` | Task-focused guide (initialising the processor, registering custom strategies, running tests, capturing logs). |
| Content authors | `devdocs/strategies.md`, `name_generator/resources/README.md` | Resource authoring workflows and data expectations. |

Additional sub-system references:

- `name_generator/README.md` – Module layout plus RNGProcessor integration notes.
- `name_generator/tools/README.md` – CLI/editor tooling, including links back to the middleware manual.

## Running the tests

Execute the automated suite from the repository root to validate gameplay strategies, middleware, and tooling scripts:

```bash
godot --headless --script res://tests/run_all_tests.gd
```

For targeted debugging, the diagnostics runner executes an individual scenario declared in the diagnostics manifest. Pass the desired ID after a double dash so Godot forwards it to the script unchanged:

```bash
godot --headless --script res://tests/run_script_diagnostic.gd -- strategy:hybrid:overlap_window
```

The example above isolates the hybrid strategy's overlap window diagnostic without replaying every manifest suite. Refer to `devdocs/tooling.md` for additional QA workflows and manifest management tips.
