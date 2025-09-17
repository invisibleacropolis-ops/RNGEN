# Dataset Production Guide

This guide covers the full lifecycle for dataset work: selecting high-quality external
lists, normalising the content, importing the data into project resources, and
identifying when to regenerate derived Markov models.

## 1. Selecting external source lists

1. Start from curated material that matches the locale and domain you want the
   generator to express. Capture those descriptors because every asset records
   them for downstream filtering (`locale`/`domain`).【F:name_generator/resources/WordListResource.gd†L15-L17】【F:name_generator/resources/SyllableSetResource.gd†L23-L27】【F:name_generator/resources/MarkovModelResource.gd†L19-L22】
2. Prefer sources that already encode frequency or popularity. You can preserve
   weights verbatim when building the word list resources (see section 2).
3. Vet the raw material for offensive, trademarked, or noisy data. Removing
   problematic entries early keeps the QA review focused on generation quality.
4. Keep a copy of the original input (CSV, spreadsheet, etc.) so the provenance
   is auditable if we ever need to retrain or add locales.

## 2. Normalising entries for import

1. Clean leading/trailing whitespace and collapse duplicates. The helper
   methods on `WordListResource` expect the `entries` array to contain a unique
   list and will expose it to strategies as-is.【F:name_generator/resources/WordListResource.gd†L10-L25】
2. Preserve weighting when it is available. You can either set a parallel
   `weights` array (matching the order of `entries`) or provide explicit
   dictionaries in `weighted_entries`; both paths ultimately yield the
   `{ "value": ..., "weight": ... }` structure consumed by the selection
   helpers.【F:name_generator/resources/WordListResource.gd†L27-L55】
3. Annotate the locale/domain metadata before saving so downstream consumers
   can filter or compose lists that share a linguistic footprint.【F:name_generator/resources/WordListResource.gd†L15-L17】
4. When preparing syllable material, separate fragments into prefix/middle/
   suffix buckets. Leave middles empty if the culture rarely uses bridging
   syllables, and toggle `allow_empty_middle` when middle fragments are
   optional.【F:name_generator/resources/SyllableSetResource.gd†L8-L21】

## 3. Importing into project resources

### Word lists

* Create or update a `WordListResource` (`.tres`) file containing the normalised
  entries. These resources feed the `WordlistStrategy`, which loads either
  resource paths or pre-instanced objects supplied via configuration.【F:name_generator/strategies/WordlistStrategy.gd†L13-L121】
* Set `use_weights` in the consuming strategy config when you want the runtime
  selection to honour the weighted entries you authored.【F:name_generator/strategies/WordlistStrategy.gd†L39-L147】

### Syllable sets

* Assemble syllable fragments inside a `SyllableSetResource` for use with
  `SyllableChainStrategy`. The strategy validates the prefixes/middles/suffixes
  at generation time and respects configuration flags like `require_middle` or
  custom middle syllable ranges.【F:name_generator/strategies/SyllableChainStrategy.gd†L1-L150】
* Populate the locale/domain metadata to keep the resource searchable alongside
  word lists and Markov models.【F:name_generator/resources/SyllableSetResource.gd†L23-L27】

### Markov models

* Train `MarkovModelResource` assets only when you need probabilistic token
  chaining rather than direct list selection. The `MarkovChainStrategy` loads a
  model from disk, validates its `states`, `start_tokens`, and `end_tokens`, and
  then walks the weighted transition tables during generation.【F:name_generator/resources/MarkovModelResource.gd†L5-L33】【F:name_generator/strategies/MarkovChainStrategy.gd†L4-L200】
* Rebuild models whenever you substantially change the underlying corpus (new
  locale, new domain, or major balance pass) so the transition data remains in
  sync with the source material.

## 4. Tooling during QA

### Dataset inspector script

Run the dataset inspector in headless mode to confirm every dataset folder is
reachable and populated:

```bash
godot --headless --script res://name_generator/tools/dataset_inspector.gd
```

The script walks `res://data`, reporting each directory and its immediate
contents, and warns when folders are missing or empty.【F:name_generator/tools/dataset_inspector.gd†L1-L48】 Use this before
handing datasets off for review.

### Syllable Set Builder plugin

1. Enable the **Syllable Set Builder** editor plugin and open the dock it adds
   on the right-hand side. The dock provides instructions, a text editor, and
   controls for loading existing `WordListResource` assets.【F:name_generator/tools/SyllableSetBuilder.gd†L1-L95】
2. Paste prepared words (one per line or CSV rows) or load a curated word list
   resource. The plugin deduplicates entries and reports how many were ingested
   via its status panel.【F:name_generator/tools/SyllableSetBuilder.gd†L98-L135】
3. Provide an output file name and press **Build syllable set**. The plugin
   derives prefixes/middles/suffixes, stores them in a new `SyllableSetResource`,
   and saves the file under `res://data/syllable_sets`. Status messages flag
   empty inputs or save failures during the workflow.【F:name_generator/tools/SyllableSetBuilder.gd†L136-L165】【F:name_generator/tools/SyllableSetBuilder.gd†L187-L200】

## 5. Regression validation

After updating datasets or derived resources, run the automated regression
suite to ensure the content still satisfies the strategy contracts:

```bash
godot --headless --script res://tests/run_all_tests.gd
```

Include the command and its output in QA notes so reviewers can verify the run.
