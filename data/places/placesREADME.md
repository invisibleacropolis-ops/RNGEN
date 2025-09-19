# Places Dataset Guide

This folder aggregates the resources required to assemble location names. Organise assets beneath `data/places/` using the following structure so tooling can classify each dataset:

- `wordlists/`
  - `biomes/` – Contextual tokens that establish climate or geography (e.g. `Taiga`, `Cavern`, `Archipelago`).
  - `descriptors/` – Adjectives and modifiers that nuance the biome (e.g. `Whispering`, `Sunken`, `Shattered`).
- `syllable_sets/` – Deterministic syllable banks used to build bespoke roots or suffixes when curated wordlists are unavailable.
- `markov_models/` – Serialized models trained on historical place names. Use them to synthesise base tokens that maintain linguistic tone.

Store datasets as Godot `.tres` resources (or compatible formats) so they load through the existing data pipeline. Keep filenames descriptive—`temperate_biomes.tres` communicates intent better than a numeric ID and helps when debugging failed lookups.

## Ready-to-use templates

The `data/places/templates/` folder provides example resources that adhere to
the structure described above:

- [`place_wordlist_template.tres`](templates/place_wordlist_template.tres) –
  `WordListResource` with balanced descriptor and biome phrases that you can
  reference directly as `res://data/places/templates/place_wordlist_template.tres`.
- [`place_syllable_template.tres`](templates/place_syllable_template.tres) –
  `SyllableSetResource` configured with optional middle fragments to demonstrate
  compound place roots (`res://data/places/templates/place_syllable_template.tres`).
- [`place_markov_template.tres`](templates/place_markov_template.tres) –
  `MarkovModelResource` prepared with explicit states, start tokens, and weighted
  transitions compatible with the current generator runtime
  (`res://data/places/templates/place_markov_template.tres`).
- [`roots_template.tres`](../markov_models/roots_template.tres) – Markov model
  stored alongside the shared markov assets. Load it via
  `res://data/markov_models/roots_template.tres` when you need a neutral root
  generator for experiments.

Copy and rename a template when you need a quick starting point, then replace
the placeholder entries with your curated data.

## Curated wordlists

Use the production-ready lists below to seed temperate biomes without cloning
the templates when you just need evocative building blocks:

| Resource | Scope | Notes |
| --- | --- | --- |
| `wordlists/biomes/temperate_biomes.tres` | Neutral temperate geography nouns (`Vale`, `Moor`, `Wilds`). | Works directly with `$descriptor $biome` templates and Hybrid pipelines that store the biome under an alias for later reuse. |
| `wordlists/descriptors/temperate_descriptors.tres` | Atmosphere-heavy adjectives (`Whispering`, `Sun-dappled`, `Storm-guarded`). | Pair with the biome list for quick place names or reuse as embellishments in Hybrid templates. |

## Composing place names

Several generation strategies can reference the datasets in this folder. The examples below mirror the configuration dictionaries passed to `NameGenerator.generate`.

### Template strategy

Pair curated wordlists to create evocative names when deterministic structure is preferred:

```gdscript
var config = {
    "strategy": "template",
    "template": "$descriptor $biome",
    "wordlists": {
        "descriptor": ["res://data/places/templates/place_wordlist_template.tres"],
        "biome": ["res://data/places/templates/place_wordlist_template.tres"],
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
            "markov_model_path": "res://data/markov_models/roots_template.tres",
            "store_as": "root",
        },
        {
            "strategy": "syllable",
            "syllable_set_path": "res://data/places/templates/place_syllable_template.tres",
            "store_as": "suffix",
        },
        {
            "strategy": "wordlist",
            "wordlist_paths": ["res://data/places/templates/place_wordlist_template.tres"],
            "store_as": "descriptor",
        },
    ],
    "template": "$descriptor $root$suffix",
}

```

Swap any of the templated paths above with your curated datasets to mix
bespoke descriptors, syllable suffixes, or trained Markov roots once you're
ready to graduate from the starter assets.

The hybrid chain lets you blend deterministic syllable assembly with Markov outputs, while the final template preserves control over the final rendering.

## Validation checklist

Follow the shared [dataset workflow guide](../../devdocs/tooling.md) when integrating new assets. At a minimum:

1. Run the dataset inspector to verify file discovery and highlight missing resources:
   ```bash
   godot --headless --path . --script res://name_generator/tools/dataset_inspector.gd
   ```
2. Execute the regression suites to confirm new datasets do not break strategy expectations:
   ```bash
   godot --headless --script res://tests/run_generator_tests.gd
   godot --headless --script res://tests/run_diagnostics_tests.gd
   ```

Record the command output alongside merge requests so downstream engineers can trace the validation history.
