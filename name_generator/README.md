# Name Generator Module

This module mirrors the runtime architecture described in `DevDoc.txt`. It keeps
strategy implementations, reusable resources, deterministic RNG plumbing, and
automated tests in discrete folders so engineers can evolve each concern without
colliding.

- `resources/` – Custom Godot resources (word lists, syllable sets, Markov
  models) that can be authored inside the editor.
- `strategies/` – Script logic implementing the Strategy pattern. Each
  `GeneratorStrategy` subclass consumes a configuration dictionary and a seeded
  `RandomNumberGenerator` instance.
- `utils/` – Shared helper scripts such as deterministic RNG routing and array
  selection helpers.
- `tools/` – Editor and command-line utilities that support content authoring.
- `tests/` – Regression suites executed via `tests/run_all_tests.gd`.

## Runtime singletons

`project.godot` registers two autoloads under the `name_generator/` directory:

- `RNGManager.gd` centralises deterministic random number generation. Call
  `RNGManager.set_master_seed()` (or `randomize_master_seed()`) during startup,
  then request isolated streams via `RNGManager.get_rng("gameplay")`. The
  manager can serialise its state with `save_state()` / `load_state()` so save
  files reproduce identical random sequences.
- `NameGenerator.gd` is the façade exposed to gameplay code and tools. It
  registers built-in strategies (`wordlist`, `syllable`, `template`, `markov`,
  and `hybrid`), exposes helpers (`pick_from_list`, `pick_weighted`), and routes
  `generate(config)` calls to the correct strategy while sourcing RNG streams
  from `RNGManager`.

## Strategy overview

All strategies extend `GeneratorStrategy`, which standardises configuration
validation and error reporting. The following implementations ship by default:

- **WordlistStrategy** – Combines entries from one or more
  `WordListResource` files. Supports weighted selection when the resource
  defines weights.
- **SyllableChainStrategy** – Concatenates syllables from a
  `SyllableSetResource`, smoothing boundaries and honouring minimum-length
  constraints.
- **TemplateStrategy** – Expands a template string containing bracketed tokens
  (e.g. `[title] of [place]`). Each token executes another NameGenerator
  configuration, enabling recursive composition.
- **MarkovChainStrategy** – Walks through a `MarkovModelResource` to emit names
  that mirror the training data’s statistical patterns.
- **HybridStrategy** – Executes a sequence of sub-configurations and exposes
  their results to later steps via `$alias` placeholders. This formalises the
  “hybrid generation” workflow described in the design document and provides a
  single configuration object that can chain every other strategy.

See `devdocs/strategies.md` for authoring guidance and
`tests/test_assets/*.tres` for small sample resources used by the automated
suites.

## Deterministic helpers

`ArrayUtils.gd` contains deterministic helpers that never touch Godot’s global
RNG state:

- `pick_uniform` / `pick_random_deterministic` – Select a single element from an
  array.
- `pick_weighted` / `pick_weighted_random_deterministic` – Select an element
  using weights supplied as dictionaries or `[value, weight]` pairs.
- `handle_empty_with_fallback` – Provide a fallback when an array is empty while
  still surfacing deterministic assertions in tests.

`name_generator/utils/RNGManager.gd` (class `RNGStreamRouter`) derives child RNG
instances from a root seed. Strategies use it to create per-token streams during
nested generation without mutating the parent RNG state.

## Tests

Run `godot --headless --script res://tests/run_all_tests.gd` to execute the
suite. The manifest currently includes the general `GeneratorStrategy` tests and
an integration suite that validates the hybrid generation pipeline.
