# Faction Dataset Guidelines

This folder stores vocabulary resources and helper assets for assembling procedurally generated faction titles. The generator expects the dataset to be split into curated resource buckets so hybrid strategies can build consistent, lore-friendly combinations.

## Expected vocabulary categories

Author the faction dataset as three parallel resource lists so hybrid strategies can compose names deterministically:

- **Ideology terms** – Abstract nouns or short phrases that communicate the faction's guiding philosophy (e.g. "Concord", "Iron Will", "Verdant Accord"). Keep entries title-cased because they are inserted directly into templates.
- **Structure nouns** – Collective nouns that describe the organisation type (e.g. "Order", "Syndicate", "League"). Use singular forms to avoid subject-verb agreement issues when the template adds pluralisation.
- **Location modifiers** – Geographic or cosmological anchors (e.g. "of the Sapphire Coast", "from Orion", "of Western Reach"). Store the leading preposition if one is required so templates can reuse the phrase verbatim.

Maintain each category as a dedicated Godot Resource (`.tres` or `.res`) or compatible JSON/CSV surrogate that the data conversion step can ingest. Align resource naming with the category (for example, `ideology_terms.tres`).

## Resource conversion workflow

1. **Source lists** – Collect the raw terms in plain text or spreadsheet format. Review them for duplicates, tone, and lore fit.
2. **Normalise** – Standardise capitalisation, strip trailing whitespace, and replace problematic punctuation. Apply consistent diacritics so automated QA can flag encoding regressions.
3. **Convert to Resources** – Run the existing import script (`utils/json_to_resource.gd`) or your preferred pipeline to convert the cleaned data into Godot Resource assets under `res://data/factions/`.
4. **Register in configs** – Reference the generated resources inside the faction generation strategy configuration (e.g. a `HybridStrategy` step or template parameter list).

Document any bespoke conversion steps alongside the script you used so future updates can replicate the pipeline.

## Hybrid and template patterns

Faction titles typically combine the three vocabularies using either hybrid chaining or templated substitution:

- **Hybrid chaining** – Create a `HybridStrategy` configuration where each step samples from one vocabulary. Store the generated results with aliases such as `$ideology`, `$structure`, and `$location` so the final template can arrange them.
- **Template substitution** – Define `StringName` templates like `$ideology $structure $location` or `$structure of the $ideology`. Keep multiple templates in rotation to vary cadence while preserving readability.
- **Fallback handling** – Provide at least one template that excludes the location modifier so the generator still succeeds if the dataset lacks geographic flavour entries.

See the core dataset workflow overview in [`devdocs/strategies.md`](../../devdocs/strategies.md) for guidance on plugging these resources into strategy configurations.

## Verification checklist

Run the established tooling after adding or updating faction datasets:

1. `dataset_inspector.gd` – Confirms the new `factions/` folder and highlights empty or missing resources.
2. Regression suites – Execute `godot --headless --script res://tests/run_generator_tests.gd` and `godot --headless --script res://tests/run_diagnostics_tests.gd` to ensure hybrid strategies consuming the faction data still pass and curated diagnostics stay green.

Log QA outcomes in change reviews so other engineers can trace dataset provenance and validation history.
