# Tools


CLI helpers that support data curation and QA are stored here. Each script extends `SceneTree` so it can execute headlessly and exit automatically when finished.

## dataset_inspector.gd

Walks the `res://data/` directory and prints out the contents of each dataset folder. Use it to confirm that new files have been imported correctly or to highlight empty directories that need attention.

```bash
godot --headless --path . --script res://name_generator/tools/dataset_inspector.gd
```

Add new scripts alongside `dataset_inspector.gd` and update the developer docs (`devdocs/tooling.md`) when you introduce additional workflows.

This directory hosts editor tooling that supports designers while curating data for the procedural name generator.

For middleware-specific automation guidance (attaching `DebugRNG`, enumerating strategies, or sourcing deterministic streams), see `docs/rng_processor_manual.md` and the workflow examples in `devdocs/rng_processor.md`.

## Syllable Set Builder

The `SyllableSetBuilder` editor plugin adds a dock that converts curated word lists into [`SyllableSetResource`](../resources/SyllableSetResource.gd) files. Enable the plugin from **Project → Project Settings → Plugins** and look for *Syllable Set Builder*.

### Supported inputs

- **Plain text** – Paste one entry per line. Blank lines and lines starting with `#` are ignored. If a comma is present the first value is used; the remaining columns can carry optional notes such as weights.
- **CSV extracts** – Paste comma-separated rows where the first column contains the word. Additional columns are ignored.
- **`WordListResource` assets** – Use the **Load WordListResource...** button to import either the `entries` array or the `weighted_entries[].value` fields from an existing resource.

### Output

The tool applies the project’s heuristic syllabification algorithm, treating the first syllable of each word as a prefix, optional interior syllables as middles, and the final syllable as a suffix. Single-syllable words are stored as both prefixes and suffixes so that generated names can stand alone. Results are saved inside `res://data/syllable_sets/` as `.tres` resources.

After building a set you can review or fine-tune the generated syllables directly in the saved resource.


