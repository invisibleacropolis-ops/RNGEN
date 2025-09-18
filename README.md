# RNGEN Deterministic Name Generation Suite

RNGEN is a Godot 4.4 project that delivers deterministic, fully-auditable name
generation for gameplay systems, authoring tools, and forthcoming platform
interfaces. Three cooperating singletons form the runtime backbone:

- **`RNGManager`** – Hands out isolated `RandomNumberGenerator` streams derived
  from a master seed, supports save/load persistence, and protects against
  accidental global RNG usage.【F:autoloads/RNGManager.gd†L1-L78】
- **`NameGenerator`** – Registers and orchestrates the strategy catalogue while
  sourcing deterministic streams, exposing helpers for common list selection
  patterns alongside the primary `generate()` façade.【F:name_generator/NameGenerator.gd†L1-L159】
- **`RNGProcessor`** – Middleware that fronts the generator with telemetry-rich
  lifecycle signals, seed governance, and DebugRNG integrations that the
  platform GUI and automation harnesses already consume.【F:name_generator/RNGProcessor.gd†L1-L126】【F:devdocs/rng_processor_manual.md†L1-L75】

Together they ensure any configuration, tool, or integration can reproduce the
same results when given the same seed, while emitting the context needed for QA
triage and analytics.

## Repository layout

| Path | Purpose |
| --- | --- |
| `autoloads/` | Root-level autoload scripts, currently limited to `RNGManager`, which the project registers globally for deterministic stream distribution.【F:autoloads/RNGManager.gd†L1-L78】 |
| `name_generator/` | The core module containing the generator façade, middleware, strategies, shared utilities, dedicated tests, and supporting tools.【F:name_generator/README.md†L1-L62】 |
| `data/` | Curated resources (word lists, syllable sets, Markov models, and themed vocabularies) organised by content domain for direct consumption by strategies and hybrid pipelines.【F:data/README.md†L1-L15】 |
| `devdocs/` | Deep-dive implementation guides that document datasets, strategies, tooling, RNG middleware, sentences, and platform GUI handbooks for every engineering discipline.【F:devdocs/README.md†L1-L16】 |
| `tests/` | Headless harness backed by `tests/test_suite_runner.gd` plus grouped CLI entry points (`run_generator_tests.gd`, `run_platform_gui_tests.gd`, and `run_diagnostics_tests.gd`) that stream manifest runs into structured summaries for CI.【F:tests/test_suite_runner.gd†L1-L160】【F:tests/run_generator_tests.gd†L1-L36】【F:tests/run_platform_gui_tests.gd†L1-L36】 |
| `Main_Interface.tscn` / `Main_Interface.gd` | Default scene for the Platform GUI shell; bootstraps the editor interface showcased in the handbook and covered by the interface regression suite.【F:Main_Interface.tscn†L1-L53】【F:Main_Interface.gd†L1-L140】 |
| `tools/` | Workspace-level automation and helper scripts (e.g., regression hooks) complementing the module-level tools shipped with the generator. |
| `addons/` | Godot editor plugins (such as the Syllable Set Builder) that streamline dataset preparation inside the editor.【F:devdocs/datasets.md†L60-L86】 |

Refer to the `Python Godot Automation Design Bible.txt` for the original design
intent; the devdocs bring every subsystem up to date with the current scripts.

## Runtime architecture

### RNGManager – deterministic stream router

`autoloads/RNGManager.gd` is responsible for deriving stream-specific seeds from
the active master seed, caching `RandomNumberGenerator` instances per named
stream, and serialising all state for persistence.【F:autoloads/RNGManager.gd†L1-L78】
Key behaviours:

- `set_master_seed()` re-seeds every cached stream so existing handles continue
  generating deterministic sequences after a master seed swap.【F:autoloads/RNGManager.gd†L17-L23】
- `randomize_master_seed()` supplies a fresh seed sourced from a temporary RNG
  so tooling can log reproducible seeds when exploring new content.【F:autoloads/RNGManager.gd†L25-L32】
- `save_state()` / `load_state()` emit and ingest dictionaries containing each
  stream’s `seed` and `state`, enabling save games and tests to capture exact RNG
  positions.【F:autoloads/RNGManager.gd†L34-L72】

### NameGenerator – strategy façade

`name_generator/NameGenerator.gd` registers the built-in strategies on `_ready()`
and exposes three tiers of functionality: utility selection helpers, strategy
registry management, and the `generate()` execution path.【F:name_generator/NameGenerator.gd†L1-L110】
Highlights include:

- Helper methods (`pick_from_list`, `pick_weighted`) route through deterministic
  RNG streams so even ad hoc selections respect the master seed.【F:name_generator/NameGenerator.gd†L20-L38】
- Strategy registration validates identifiers, ensures each implementation
  extends `GeneratorStrategy`, and keeps DebugRNG in sync so telemetry stays
  comprehensive.【F:name_generator/NameGenerator.gd†L40-L103】【F:name_generator/NameGenerator.gd†L228-L274】
- `generate(config)` normalises the request, derives or respects explicit
  `rng_stream` overrides, and returns either the strategy payload or a structured
  error dictionary for clients to inspect.【F:name_generator/NameGenerator.gd†L105-L204】

### RNGProcessor – middleware and observability layer

`name_generator/RNGProcessor.gd` fronts the generator with a defensive API that
mirrors strategy metadata, enforces seed handling, and emits lifecycle signals
for tooling and UI layers.【F:name_generator/RNGProcessor.gd†L1-L134】 The processor:

- Provides `initialize_master_seed`, `randomize_master_seed`, and `get_master_seed`
  wrappers that proxy to `RNGManager` when available or fall back to hashed local
  streams inside tests.【F:name_generator/RNGProcessor.gd†L18-L72】
- Exposes `list_strategies()` / `describe_strategies()` so external clients can
  stay decoupled from the generator’s internal registry while still receiving
  expected configuration schemas.【F:name_generator/RNGProcessor.gd†L74-L121】
- Emits `generation_started`, `generation_completed`, and `generation_failed`
  with metadata describing the resolved strategy, seed, and RNG stream, creating a
  stable surface for the Platform GUI’s timelines and QA dashboards.【F:name_generator/RNGProcessor.gd†L5-L63】【F:name_generator/RNGProcessor.gd†L123-L174】
- Supports opt-in DebugRNG logging, automatically attaching/unattaching helpers
  and forwarding per-stream usage context so TXT reports capture every
  derivation.【F:name_generator/RNGProcessor.gd†L176-L246】【F:devdocs/rng_processor_manual.md†L75-L154】

## Strategy catalogue

All strategies extend `GeneratorStrategy` and are registered by default when the
`NameGenerator` singleton initialises.【F:name_generator/NameGenerator.gd†L112-L146】 Current
implementations are:

- **WordlistStrategy** – Loads one or more `WordListResource` assets, supports
  weighted or uniform selection, and validates each entry before emission.【F:name_generator/strategies/WordlistStrategy.gd†L13-L147】
- **SyllableChainStrategy** – Builds names by chaining prefixes, middles, and
  suffixes from `SyllableSetResource` assets while honouring optional middle
  syllables and minimum length requirements.【F:name_generator/strategies/SyllableChainStrategy.gd†L1-L150】
- **TemplateStrategy** – Expands bracketed tokens (e.g. `[title]`) by dispatching
  nested generator configurations, enabling recursive grammar-like workflows.【F:name_generator/strategies/TemplateStrategy.gd†L1-L210】
- **MarkovChainStrategy** – Walks trained transition tables from
  `MarkovModelResource` assets to recreate statistical patterns from source
  corpora.【F:name_generator/strategies/MarkovChainStrategy.gd†L4-L200】
- **HybridStrategy** – Executes ordered sub-steps, exposing intermediate results
  via `$alias` placeholders so complex pipelines can combine every other
  strategy.【F:name_generator/strategies/HybridStrategy.gd†L1-L210】

See `devdocs/strategies.md` for configuration recipes, schema expectations, and
error-handling guidelines across the catalogue.

## Data resources and authoring pipeline

The `data/` tree stores the resources consumed by strategies in production and
during tests. Each subfolder captures a content domain (people, places, factions,
monsters, etc.) so authors can iterate on focussed vocabularies.【F:data/README.md†L3-L15】

`devdocs/datasets.md` documents the full lifecycle for sourcing, normalising,
and importing lists into custom Godot resources. It details how `WordListResource`
records locale/domain metadata and weighting, how `SyllableSetResource` encodes
prefix/middle/suffix fragments, and when to regenerate `MarkovModelResource`
artifacts.【F:devdocs/datasets.md†L1-L73】 The guide also covers QA tooling:

- **Dataset inspector** (`name_generator/tools/dataset_inspector.gd`) walks the
  `res://data` tree and flags empty or missing directories so dataset bundles are
  review-ready.【F:devdocs/datasets.md†L60-L73】
- **Syllable Set Builder** editor plugin deduplicates source words, extracts
  syllables, and saves new `SyllableSetResource` assets directly into the data
  tree with status feedback for every stage.【F:devdocs/datasets.md†L75-L108】

## Tooling and automation support

Beyond dataset helpers, several scripts enable rigorous QA and integration:

- **DebugRNG** (`name_generator/tools/DebugRNG.gd`) captures structured TXT
  reports, including session metadata, per-request timelines, warnings, and RNG
  stream usage summaries. Attach it through `RNGProcessor.set_debug_rng(...)` or
  directly via `debug_rng.attach_to_processor(...)` to trace complex runs.【F:devdocs/rng_processor_manual.md†L95-L154】
- **Headless diagnostics** – The test harness can execute targeted diagnostics by
  calling `tests/run_script_diagnostic.gd` with a manifest ID, allowing engineers
  to replay specific failure scenarios without rerunning every grouped
  manifest.【F:tests/run_script_diagnostic.gd†L1-L140】
- **Command-line tooling** – `devdocs/tooling.md` enumerates CLI utilities for
  dataset verification, manifest maintenance, and regression workflows to support
  both gameplay engineers and content authors.

## Developer workflows

### Integrating in gameplay or tools

Follow the `RNGProcessor Field Guide` when wiring the middleware into runtime
scenes or external automation. Seed the processor once during bootstrap via
`RNGProcessor.randomize_master_seed()` (or restore a saved seed) and then call
`RNGProcessor.generate(config)` for every name request. The middleware mirrors the
strategy registry, so dropdowns can be populated with `list_strategies()` /
`describe_strategies()` without reaching into `NameGenerator` internals.【F:devdocs/rng_processor.md†L1-L55】

### Extending the strategy catalogue

To introduce a new generator:

1. Implement a `GeneratorStrategy` subclass following the scaffolding described
   in `devdocs/strategies.md`.
2. Register it during startup via `NameGenerator.register_strategy(...)` so both
   the generator and middleware expose it immediately.【F:name_generator/NameGenerator.gd†L40-L112】
3. Add focused tests and, if needed, DebugRNG hooks to document new error modes
   in shared logs.【F:name_generator/NameGenerator.gd†L228-L274】【F:devdocs/rng_processor_manual.md†L95-L154】

### Maintaining datasets

When adding or updating resources:

1. Source and clean entries as described in the dataset guide, preserving weights
   and metadata for downstream filtering.【F:devdocs/datasets.md†L1-L43】
2. Save resources into the appropriate domain folder under `data/`.
3. Run the dataset inspector and regression suite to confirm deterministic
   guarantees remain intact before shipping.【F:devdocs/datasets.md†L60-L108】【F:devdocs/datasets.md†L116-L119】

## Documentation index

Start with the developer documentation map for discipline-specific guidance:

- `devdocs/datasets.md` – Dataset sourcing, normalisation, and QA scripts.
- `devdocs/strategies.md` – Strategy configuration keys, validation behaviour,
  and implementation recipes.
- `devdocs/tooling.md` – CLI usage notes and automation workflows.
- `devdocs/sentences.md` – Template and hybrid sentence builders, including
  seeding tips.
- `devdocs/rng_processor.md` & `devdocs/rng_processor_manual.md` – Middleware API,
  DebugRNG logging, and platform integration reference.
- `devdocs/platform_gui_handbook.md` – Platform GUI tabs, batch export workflows,
  replay tooling, and accessibility considerations.
- `devdocs/platform_gui_checklists.md` – Printable launch, export, and debug handoff
  checklists that mirror the handbook.

These documents expand on every script and workflow mentioned in this README and
should be treated as the canonical reference for engineers joining the project.

## Testing and quality assurance

Execute grouped manifest runs from the project root to mirror the QA panel:

```bash
godot --headless --script res://tests/run_generator_tests.gd
godot --headless --script res://tests/run_platform_gui_tests.gd
godot --headless --script res://tests/run_diagnostics_tests.gd
```

The generator suite covers strategy and middleware scenarios, the platform GUI
suite exercises editor tooling (including the `Main_Interface` shell scene), and
the diagnostics suite replays curated scenarios listed in
`tests/tests_manifest.json`. Each script streams results, aggregates failures,
and exits non-zero when a suite fails so CI logs stay actionable.【F:tests/run_generator_tests.gd†L1-L36】【F:tests/run_platform_gui_tests.gd†L1-L36】【F:tests/run_diagnostics_tests.gd†L1-L36】【F:tests/interface/test_main_interface_scene.gd†L1-L170】 Use
`--diagnostic-id` with `tests/run_script_diagnostic.gd` to isolate individual
checks during investigation.【F:tests/run_script_diagnostic.gd†L1-L140】 Attach
DebugRNG logs to QA reports whenever deterministic reproduction details are
required.

The Platform GUI bundles a dedicated QA panel
(`res://addons/platform_gui/panels/qa/QAPanel.tscn`) that wraps these headless
commands, streams log output while suites execute, and records recent runs with
links to the generated log files.【F:addons/platform_gui/panels/qa/QAPanel.gd†L1-L268】
Use the panel for exploratory testing or quick repro captures, but always export
the full console transcript when running headless in CI so downstream reviewers
can audit every warning and failure line without launching Godot.【F:devdocs/tooling.md†L1-L120】

## Platform GUI readiness

The forthcoming Platform GUI consumes the middleware APIs outlined here:

- Strategy metadata flows from `RNGProcessor.describe_strategies()`.
- Execution timelines bind to the lifecycle signals emitted during each
  generation request.
- DebugRNG session metadata and stream usage power troubleshooting panels.

By keeping integrations pointed at the processor and DebugRNG, new UI features or
external automation can evolve without taking direct dependencies on strategy
internals, preserving the deterministic contract across the project.【F:devdocs/rng_processor_manual.md†L155-L181】
