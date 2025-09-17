# Data Directory

This directory organizes external assets and reference materials used by the random name generator. Each subfolder mirrors a different data source that the generator can load at runtime.

- `markov_models/` – Serialized Markov chains or similar statistical models for constructing names from character sequences.
- `syllable_sets/` – Collections of syllable groupings that allow deterministic assembly of pronounceable tokens.
- `wordlists/` – Curated name lists that can be sampled directly or used to seed other algorithms.
- `objects/` – Optional thematic lists for inanimate objects or artifacts used in specialized generators.
- `people/` – Optional demographic-specific lists or metadata used to produce person names.
- `skills_powers/` – Ability-focused vocabularies (verbs, elements, suffixes) for combat skills, spells, and powers.
- `places/` – Wordlists, syllable sets, and Markov models tailored for location names. See `data/places/README.md` for compositional guidance.


Add additional folders as needed for other content groupings. Place `.gdignore` files inside any folder containing raw data to prevent the Godot importer from processing unsupported formats.
