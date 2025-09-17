# Tools

This directory hosts editor tooling that supports designers while curating data for the procedural name generator.

## Syllable Set Builder

The `SyllableSetBuilder` editor plugin adds a dock that converts curated word lists into [`SyllableSetResource`](../resources/SyllableSetResource.gd) files. Enable the plugin from **Project → Project Settings → Plugins** and look for *Syllable Set Builder*.

### Supported inputs

- **Plain text** – Paste one entry per line. Blank lines and lines starting with `#` are ignored. If a comma is present the first value is used; the remaining columns can carry optional notes such as weights.
- **CSV extracts** – Paste comma-separated rows where the first column contains the word. Additional columns are ignored.
- **`WordListResource` assets** – Use the **Load WordListResource...** button to import either the `entries` array or the `weighted_entries[].value` fields from an existing resource.

### Output

The tool applies the project’s heuristic syllabification algorithm, treating the first syllable of each word as a prefix, optional interior syllables as middles, and the final syllable as a suffix. Single-syllable words are stored as both prefixes and suffixes so that generated names can stand alone. Results are saved inside `res://data/syllable_sets/` as `.tres` resources.

After building a set you can review or fine-tune the generated syllables directly in the saved resource.

