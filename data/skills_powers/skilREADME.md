# Skills & Powers Datasets

This folder stores curated vocabularies for combat arts, magical disciplines, and other ability-driven name sets. Each dataset should be authored as a Godot `Resource` so designers can preview and tune entries inside the editor.

## Required resources

Populate the directory with the following resource files:

- **Action verbs** – A `WordListResource` containing aggressive or supportive verbs (e.g. *Cleave*, *Ward*, *Entwine*) used as leading tokens.
- **Elemental themes** – A `WordListResource` that lists damage types, schools of magic, or power sources (e.g. *Ember*, *Tempest*, *Void*).
- **Suffixes & forms** – Either a second `WordListResource` or a focused `SyllableSetResource` that adds finishing flourishes such as *-burst*, *-ritual*, or *-form*.

Name files descriptively (for example `action_verbs.tres`, `elemental_themes.tres`, and `suffixes.tres`) so downstream configs remain self-documenting.

## Conversion & verification workflow

1. Collect raw terms in a plain-text or CSV scratch file.
2. Follow the dataset conversion pipeline in [`devdocs/tooling.md`](../../devdocs/tooling.md) to transform the source list into editor-friendly resources:
   - Use the **Syllable Set Builder** for syllable-driven suffix packs when you want procedural variations.
   - Save word lists with the Godot inspector to ensure `.tres` metadata stays consistent with the project defaults.
3. Run the verification steps from the same workflow doc to confirm the assets import correctly:
   - Execute `godot --headless --path . --script res://name_generator/tools/dataset_inspector.gd` to verify the new files appear under `skills_powers`.
   - Spot-check the resources inside the Godot editor to confirm the `entries` arrays and weights are correct.

## Sample generation configs

Hybrid and template strategies can consume the datasets directly. The following examples assume the resources live under `res://data/skills_powers/`:

```gdscript
var hybrid_config := {
    "strategy": "hybrid",
    "seed": "qa_skill_demo",
    "steps": [
        {
            "strategy": "wordlist",
            "wordlist_paths": ["res://data/skills_powers/action_verbs.tres"],
            "store_as": "verb",
        },
        {
            "strategy": "wordlist",
            "wordlist_paths": ["res://data/skills_powers/elemental_themes.tres"],
            "store_as": "element",
        },
        {
            "strategy": "wordlist",
            "wordlist_paths": ["res://data/skills_powers/suffixes.tres"],
            "store_as": "suffix",
        },
    ],
    "template": "$verb of $element $suffix",
}
```

```gdscript
var template_config := {
    "strategy": "template",
    "seed": "qa_skill_demo",
    "wordlists": {
        "verb": "res://data/skills_powers/action_verbs.tres",
        "element": "res://data/skills_powers/elemental_themes.tres",
        "suffix": "res://data/skills_powers/suffixes.tres",
    },
    "template": "$verbing $element $suffix",
}
```

Adjust templates to fit your game’s tone while keeping placeholders aligned with the resource names.

## Regression checks

After updating any dataset in this folder, run the project’s regression tests to catch integration issues early:

- `godot --headless --script res://name_generator/tools/dataset_inspector.gd`
- `godot --headless --script res://tests/run_generator_tests.gd`
- `godot --headless --script res://tests/run_diagnostics_tests.gd`

The latter commands execute the generator suites and curated diagnostics, ensuring hybrid and template compositions still succeed with the refreshed data.
