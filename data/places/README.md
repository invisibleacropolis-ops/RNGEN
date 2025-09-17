# Places Dataset Guide

This folder aggregates the resources required to assemble location names. Organise assets beneath `data/places/` using the following structure so tooling can classify each dataset:

- `wordlists/`
  - `biomes/` – Contextual tokens that establish climate or geography (e.g. `Taiga`, `Cavern`, `Archipelago`).
  - `descriptors/` – Adjectives and modifiers that nuance the biome (e.g. `Whispering`, `Sunken`, `Shattered`).
- `syllable_sets/` – Deterministic syllable banks used to build bespoke roots or suffixes when curated wordlists are unavailable.
- `markov_models/` – Serialized models trained on historical place names. Use them to synthesise base tokens that maintain linguistic tone.

Store datasets as Godot `.tres` resources (or compatible formats) so they load through the existing data pipeline. Keep filenames descriptive—`temperate_biomes.tres` communicates intent better than a numeric ID and helps when debugging failed lookups.

## Composing place names

Several generation strategies can reference the datasets in this folder. The examples below mirror the configuration dictionaries passed to `NameGenerator.generate`.

### Template strategy

Pair curated wordlists to create evocative names when deterministic structure is preferred:

```gdscript
var config = {
    "strategy": "template",
    "template": "$descriptor $biome",
    "wordlists": {
        "descriptor": ["res://data/places/wordlists/descriptors/mystic_descriptors.tres"],
        "biome": ["res://data/places/wordlists/biomes/mountain_biomes.tres"],
    },
}
```

The `template` strategy keeps ordering explicit and allows you to reuse the same descriptor or biome list across multiple templates by adjusting the placeholders.

### Hybrid strategy

Use `HybridStrategy` when you need to merge statistical models with curated fragments:

```gdscript
var config = {
    "strategy": "hybrid",
    "seed": "atlas_demo_seed",
    "steps": [
        {
            "strategy": "markov",
            "markov_model_path": "res://data/places/markov_models/coastal_roots.tres",
            "store_as": "root",
        },
        {
            "strategy": "syllable",
            "syllable_set_path": "res://data/places/syllable_sets/shore_suffixes.tres",
            "store_as": "suffix",
        },
        {
            "strategy": "wordlist",
            "wordlist_paths": ["res://data/places/wordlists/descriptors/nautical_descriptors.tres"],
            "store_as": "descriptor",
        },
    ],
    "template": "$descriptor $root$suffix",
}
```

The hybrid chain lets you blend deterministic syllable assembly with Markov outputs, while the final template preserves control over the final rendering.

## Validation checklist

Follow the shared [dataset workflow guide](../../devdocs/tooling.md) when integrating new assets. At a minimum:

1. Run the dataset inspector to verify file discovery and highlight missing resources:
   ```bash
   godot --headless --path . --script res://name_generator/tools/dataset_inspector.gd
   ```
2. Execute the regression suite to confirm new datasets do not break strategy expectations:
   ```bash
   godot --headless --script res://tests/run_all_tests.gd
   ```

Record the command output alongside merge requests so downstream engineers can trace the validation history.
