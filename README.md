# RNGEN – Random Name Generator Toolkit

RNGEN is a Godot 4 project that experiments with reusable building blocks for random name generation. The repository contains data-driven resources, reusable generation strategies, and lightweight utilities that make it easier to iterate on algorithm prototypes.

## Project layout

```
res://
├── data/                     # Source data, Markov models, and curated word lists
│   ├── markov_models/        # Serialized statistical models consumed by generators
│   └── ...
├── name_generator/           # Reusable scripts, strategies, tools, and tests
│   ├── resources/            # Godot resources shared across the generator
│   ├── strategies/           # `GeneratorStrategy` subclasses
│   ├── utils/                # Shared helper modules (e.g., deterministic RNG helpers)
│   ├── tools/                # Editor/CLI scripts for authoring and validation
│   └── tests/                # Automated checks and smoke-test scripts
└── project.godot             # Root Godot project file
```

### Data directories

The `data/` tree mirrors the runtime datasets you want to plug into different strategies. Add new folders for custom themes (for example `objects/`, `people/`, or `syllable_sets/`). Drop a `.gdignore` file next to raw assets that should not be imported by Godot. See [`data/README.md`](data/README.md) for an expanded description of each folder.

### Autoloads

The project currently does not register any autoload singletons in `project.godot`; strategies are loaded explicitly by whichever scene or tool needs them. If you introduce a frequently used service, define it in `project.godot`'s `[autoload]` section and document the resulting singleton here so that downstream engineers know which global APIs are available.

## Strategy configuration overview

All name-generation strategies inherit from [`GeneratorStrategy.gd`](name_generator/strategies/GeneratorStrategy.gd). The base class enforces a declarative configuration contract via the protected `_get_expected_config_keys()` helper. Subclasses list required keys (as strings) and optional keys (mapped to their expected Godot variant type):

```gdscript
func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(["culture", "min_length"]),
        "optional": {
            "max_length": TYPE_INT,
            "syllable_bias": TYPE_FLOAT,
        },
    }
```

At runtime the base `_validate_config()` helper checks the provided dictionary, returning rich `GeneratorError` instances when the contract is violated. Strategies can surface these errors directly to their callers to produce consistent diagnostics.

## RNG workflow

Deterministic randomness is central to repeatable generation. Strategies should always accept a caller-supplied [`RandomNumberGenerator`](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html) and hand it to the utilities in [`ArrayUtils.gd`](name_generator/utils/ArrayUtils.gd) instead of touching global random state. The helper functions (`pick_random_deterministic`, `pick_weighted_random_deterministic`, and `handle_empty_with_fallback`) never read from global RNGs, making it safe to seed the provided generator for testing or serialization workflows.

A typical `generate()` implementation therefore:

1. Calls `_validate_config(config)` to obtain an optional `GeneratorError`.
2. Seeds or rewinds the shared RNG if the caller supplied seed metadata.
3. Uses `ArrayUtils` helpers to make deterministic selections from curated lists or weighted entries.
4. Assembles the final name string and returns it to the caller.

## Running tests and authoring scripts

The repository ships with lightweight scripts to keep the workflow reproducible:

- **Smoke tests** – Execute deterministic checks for utility helpers via the `name_generator/tests/smoke_test.gd` runner:

  ```bash
  godot --headless --path . --script res://name_generator/tests/smoke_test.gd
  ```

- **Data inspection tool** – Summarise available datasets and highlight empty folders:

  ```bash
  godot --headless --path . --script res://name_generator/tools/dataset_inspector.gd
  ```

Run both commands from the repository root. Godot 4 must be available on your `$PATH` for the scripts to execute.

## Additional documentation

The [`devdocs/`](devdocs/README.md) directory collects deep dives for engine integrators, including strategy authoring tips, configuration key references, and usage guidelines for the tooling scripts.
