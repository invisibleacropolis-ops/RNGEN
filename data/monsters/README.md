# Monster Datasets

This folder houses resources that describe the studio's bestiary. Populate it with custom Godot resources that capture the anatomy, behaviour, and vocal signatures of the creatures your Hybrid strategies will compose.

## Core datasets

### Anatomy descriptors

Provide `WordListResource` assets that catalogue:

- **Body plans** – Primary silhouettes (quadruped, serpentine, avian) and anatomical variations (multiple limbs, carapaces).
- **Textures and materials** – Skin, scale, fur, and exoskeleton descriptors, including colours and surface qualities.
- **Anatomical modifiers** – Horn configurations, wing structures, tail types, sensory organs, and elemental infusions.

Keep each list scoped to a single concept so Hybrid templates can mix and match descriptors without duplicating data. When curating entries, stick to lowercase tokens; Template and Hybrid strategies can capitalise or stylise as needed.

### Behaviour lexicon

Author complementary `WordListResource` files that describe behaviours, combat styles, and habitats. Break the catalogue into focused themes such as "aggressive openers", "territorial responses", "habitat-specific verbs", and "social patterns". These datasets feed into descriptive suffixes (e.g., "that stalks the dunes") or title prefixes ("The Cradle-Watcher").

## Creature vocalisation data

### Syllable sets

1. Collect reference audio or lore notes that illustrate the creature's calls.
2. Transcribe representative sounds into phonetic syllables (e.g., `kra`, `ghul`, `ith`).
3. In the Godot editor, create a new `SyllableSetResource` and paste the syllables into the exported arrays (prefix/mid/suffix). Group guttural, hissing, or shrieking patterns into separate resources when the species exhibits multiple vocal registers.
4. Save the `.tres` files under `data/syllable_sets/monsters/` and reference them from this folder's documentation or Hybrid configs.

### Markov models

1. Build a source list of canonical monster cries or name stems (game lore, tabletop bestiaries, audio transcripts).
2. Normalise spellings so similar phonemes share the same characters—Markov quality depends on consistent tokens.
3. Train a `MarkovModelResource` using the workflow in [`DevDoc.txt`](../../DevDoc.txt) Chapter 7 (Markov Chains). Export the resulting `.tres` into `data/markov_models/monsters/` and annotate its intent in this folder.
4. Record the training corpus and parameters in a sibling Markdown file so QA can reproduce the model.

## Hybrid strategy examples

Use Hybrid chains to blend anatomical data with vocal signatures. Example configuration:

```gdscript
var config := {
    "strategy": "hybrid",
    "seed": "monster_demo_seed",
    "steps": [
        {
            "strategy": "wordlist",
            "wordlist_paths": ["res://data/monsters/body_plans.tres"],
            "store_as": "body"
        },
        {
            "strategy": "markov",
            "markov_model_path": "res://data/markov_models/monsters/guttural_calls.tres",
            "store_as": "call"
        },
        {
            "strategy": "syllable",
            "syllable_set_path": "res://data/syllable_sets/monsters/razor_suffixes.tres",
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
- Execute the project test suite after adding or updating datasets:
  ```bash
  godot --headless --script res://tests/run_all_tests.gd
  ```
- Follow the shared dataset workflow procedures outlined in [`devdocs/tooling.md`](../../devdocs/tooling.md) for import automation, naming conventions, and documentation updates.
