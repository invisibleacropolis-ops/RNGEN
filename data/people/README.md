# People Names Data

This directory houses the curated datasets that feed the people-focused name
generation strategies. Populate it with raw source material (CSV, TSV, or text
exports) that can be normalised into Godot `Resource` assets so designers can
drop them directly into strategy configurations. Refer to the
[dataset workflow guide](../../devdocs/dataset_workflow.md) for the end-to-end
pipeline that turns vendor datasets into ready-to-ship `.tres` files.

## Required raw lists

Author the following lists before you begin converting anything into resources:

- **Given names** – Localised first-name catalogues for each demographic you
  plan to support. Capture gender variations as separate files when relevant so
  strategy authors can opt into deterministic subsets.
- **Surnames** – Family names grouped by culture or linguistic family. Maintain
  a consistent casing and remove duplicates so Markov training remains stable.
- **Honorifics and titles** – Prefixes such as `Dr.`, `Captain`, or regional
  forms of address. These power hybrid templates that stitch together titles and
  generated roots.

Keep a companion metadata sheet (e.g. spreadsheet with provenance, licence,
normalisation notes) so reviewers can quickly audit the source.

## Converting raw lists into resources

Once the raw lists are vetted, convert them into Godot-native assets so tooling
and strategies share the same inputs.

### Word lists → `WordListResource`

1. Launch Godot and open the project.
2. Right-click inside `res://data/wordlists/people/` and choose **New Resource…**.
3. Search for `WordListResource` and create a new `.tres` file (e.g.
   `given_names_en_female.tres`).
4. Paste your list into the `words` array in the Inspector, preserving one entry
   per element. Use the **Sort** button to keep ordering deterministic when
   weights are not supplied.
5. Commit the `.tres` file alongside a short changelog entry describing the
   source and any filters applied.

Use these assets with the word list strategy:

```gdscript
{
    "strategy": "wordlist",
    "seed": "people_wordlist_demo",
    "wordlist_paths": [
        "res://data/wordlists/people/given_names_en_female.tres"
    ],
    "use_weights": false
}
```

### Syllable lists → `SyllableSetResource`

Split your cleaned name lists into syllables when you need novel-but-themed
outputs (e.g. fantasy clans or alien dialects).

1. Create a new `SyllableSetResource` under `res://data/syllable_sets/people/`.
2. Populate `prefixes`, `middles`, and `suffixes` arrays. Leave `middles` empty
   if you only want two-part constructions.
3. Optional: maintain parallel `weights` arrays when you need biased syllable
   selection—see the dataset workflow guide for preprocessing helpers.

Reference the syllable set in configs like:

```gdscript
{
    "strategy": "syllable",
    "seed": "people_syllable_demo",
    "syllable_set_path": "res://data/syllable_sets/people/fantasy_clan.tres",
    "require_middle": true,
    "min_length": 2,
    "max_length": 4
}
```

### Markov training → `MarkovModelResource`

1. Export a deduplicated list of example names (CSV or TXT) that reflects the
   style you want the model to mimic.
2. Run the training workflow outlined in the dataset guide to convert the raw
   list into a transition table. The tooling serialises the result into a
   `MarkovModelResource` saved under `res://data/markov_models/people/`.
3. Inspect the generated `.tres` in Godot to confirm state counts, token
   coverage, and optional temperature overrides.

Consume the model with the Markov strategy:

```gdscript
{
    "strategy": "markov",
    "seed": "people_markov_demo",
    "markov_model_path": "res://data/markov_models/people/modern_us.tres",
    "max_length": 12,
    "temperature": 0.9
}
```

## When to chain datasets with Hybrid configs

Use `HybridStrategy` whenever a character concept spans multiple datasets or
requires deterministic templating. Common scenarios include:

- Combining an honorific, given name, and surname sourced from separate lists.
- Appending syllable-derived epithets or clan names to a Markov-generated root.
- Producing localisation-friendly outputs where each segment comes from a
  culture-specific dataset.

Hybrid configurations sequence individual strategy payloads and then stitch the
results with an optional template:

```gdscript
{
    "strategy": "hybrid",
    "seed": "people_hybrid_demo",
    "steps": [
        {
            "strategy": "wordlist",
            "wordlist_paths": [
                "res://data/wordlists/people/honorifics_generic.tres"
            ],
            "store_as": "title"
        },
        {
            "strategy": "markov",
            "markov_model_path": "res://data/markov_models/people/modern_us.tres",
            "store_as": "core"
        },
        {
            "strategy": "wordlist",
            "wordlist_paths": [
                "res://data/wordlists/people/surnames_en.tres"
            ],
            "store_as": "surname"
        }
    ],
    "template": "$title $core $surname"
}
```

Because each step receives a deterministic RNG stream derived from the top-level
seed, rerunning the configuration reproduces the full name without additional
state tracking.

## QA checklist for new or updated datasets

- Run the dataset inspector to confirm the new `.tres` files are discoverable and
  free from empty arrays:

  ```bash
  godot --headless --path . --script res://name_generator/tools/dataset_inspector.gd
  ```

- Execute the hybrid test suite (or the full manifest) to ensure cross-strategy
  expectations still hold:

  ```bash
  godot --headless --path . --script res://tests/run_all_tests.gd
  ```

Document the test output in your pull request so reviewers can verify the
pipeline remains healthy.
