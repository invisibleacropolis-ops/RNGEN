# Monster Datasets

This folder houses resources that describe the studio's bestiary. Populate it with custom Godot resources that capture the anatomy, behaviour, and vocal signatures of the creatures your Hybrid strategies will compose.

## Core datasets

### Anatomy descriptors

Provide `WordListResource` assets that catalogue:

- **Body plans** – Primary silhouettes (quadruped, serpentine, avian) and anatomical variations (multiple limbs, carapaces).
- **Textures and materials** – Skin, scale, fur, and exoskeleton descriptors, including colours and surface qualities.
- **Anatomical modifiers** – Horn configurations, wing structures, tail types, sensory organs, and elemental infusions.

Starter templates live at:

- [`res://data/monsters/body_plans_template.tres`](body_plans_template.tres)
- [`res://data/monsters/textures_template.tres`](textures_template.tres)
- [`res://data/monsters/behaviours_template.tres`](behaviours_template.tres)

Ready-made examples live under `data/monsters/templates/`. Copy the
`monster_wordlist_template.tres` file to bootstrap a new list with weighting
metadata already in place.

Keep each list scoped to a single concept so Hybrid templates can mix and match descriptors without duplicating data. When curating entries, stick to lowercase tokens; Template and Hybrid strategies can capitalise or stylise as needed.

### Behaviour lexicon

Author complementary `WordListResource` files that describe behaviours, combat styles, and habitats. Break the catalogue into focused themes such as "aggressive openers", "territorial responses", "habitat-specific verbs", and "social patterns". These datasets feed into descriptive suffixes (e.g., "that stalks the dunes") or title prefixes ("The Cradle-Watcher"). Use `behaviours_template.tres` for a quick starting list and expand it into theme-specific catalogues.

## Creature vocalisation data

### Syllable sets

1. Collect reference audio or lore notes that illustrate the creature's calls.
2. Transcribe representative sounds into phonetic syllables (e.g., `kra`, `ghul`, `ith`).
3. In the Godot editor, create a new `SyllableSetResource` and paste the syllables into the exported arrays (prefix/mid/suffix). Group guttural, hissing, or shrieking patterns into separate resources when the species exhibits multiple vocal registers.
4. Save the `.tres` files under `data/syllable_sets/monsters/` and reference them from this folder's documentation or Hybrid configs.

The `monster_syllable_template.tres` example inside `data/monsters/templates/`
shows a curated prefix/middle/suffix split you can duplicate for new species.
For neutral guttural calls, load the shared
[`res://data/syllable_sets/monsters/vocalisations_template.tres`](../syllable_sets/monsters/vocalisations_template.tres)
resource and replace the syllables with species-specific phonemes.

### Markov models

1. Build a source list of canonical monster cries or name stems (game lore, tabletop bestiaries, audio transcripts).
2. Normalise spellings so similar phonemes share the same characters—Markov quality depends on consistent tokens.
3. Train a `MarkovModelResource` using the workflow in [`DevDoc.txt`](../../DevDoc.txt) Chapter 7 (Markov Chains). Export the resulting `.tres` into `data/markov_models/monsters/` and annotate its intent in this folder.
4. Record the training corpus and parameters in a sibling Markdown file so QA can reproduce the model.

For quick experiments, duplicate `monster_markov_template.tres` from
`data/monsters/templates/`. It already follows the `states`/`start_tokens`
layout required by the current `MarkovModelResource` implementation. You can
also load [`res://data/markov_models/monsters/cries_template.tres`](../markov_models/monsters/cries_template.tres)
to seed guttural cry patterns for hybrid prototypes before recording bespoke
datasets.

## Hybrid strategy examples

Use Hybrid chains to blend anatomical data with vocal signatures. Example configuration:

```gdscript
var config := {
    "strategy": "hybrid",
    "seed": "monster_demo_seed",
    "steps": [
        {
            "strategy": "wordlist",
            "wordlist_paths": ["res://data/monsters/body_plans_template.tres"],
            "store_as": "body"
        },
        {
            "strategy": "markov",
            "markov_model_path": "res://data/markov_models/monsters/cries_template.tres",
            "store_as": "call"
        },
        {
            "strategy": "syllable",
            "syllable_set_path": "res://data/syllable_sets/monsters/vocalisations_template.tres",
            "store_as": "suffix"
        }
    ],
    "template": "The $body ${call}$suffix"
}
```

Extend the chain with behaviour descriptors or habitat wordlists to produce full lore snippets (e.g., append a step that samples `res://data/monsters/habitats.tres` and interpolate it into the template).

## Quality assurance

- Run the dataset inspector to confirm the new resources appear and non-empty lists are in place:
  ```bash
  godot --headless --path . --script res://name_generator/tools/dataset_inspector.gd
  ```
- Execute the project test suites after adding or updating datasets:
  ```bash
  godot --headless --script res://tests/run_generator_tests.gd
  godot --headless --script res://tests/run_diagnostics_tests.gd
  ```
- Follow the shared dataset workflow procedures outlined in [`devdocs/tooling.md`](../../devdocs/tooling.md) for import automation, naming conventions, and documentation updates.
