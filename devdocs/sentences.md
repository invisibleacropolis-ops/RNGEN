# Formula-Driven Sentence Authoring

Designing sentence generators in RNGEN hinges on two composable strategies:

- **`TemplateStrategy`** expands bracket tokens such as `[skill_intro]` into sub-sentences.
- **`HybridStrategy`** chains multiple generator calls and exposes each result to downstream `$placeholders`.

Used together, they let you build deterministic narrative blurbs that weave in multiple datasets.

> **Workspace shortcut** – The Formulas workspace scene (`res://addons/platform_gui/workspaces/formulas/FormulasWorkspace.tscn`) ships with guided blueprints for the examples below. Each blueprint preloads the same hybrid steps, nested templates, and dataset paths documented here so artists can experiment without rebuilding the configuration from scratch.

## Token naming conventions

Template tokens are wrapped in square brackets. Each token must have an entry with the same name in the `sub_generators` dictionary. Adopt `snake_case` identifiers (e.g. `[skill_summary]`, `[faction_codename]`) so they align with configuration keys and data asset filenames.

Hybrid placeholders use a leading dollar sign (e.g. `$skill`, `$faction`). Provide stable aliases via `store_as` whenever a step should be referenced later; otherwise the step index (`$0`, `$1`, ...) becomes the placeholder. Reuse aliases sparingly—assigning distinct names keeps template strings readable and prevents accidental shadowing when you refactor pipelines.

## Recursion limits and nesting depth

`TemplateStrategy` guards against runaway recursion through `max_depth` (default `8`). Each time a template token triggers another generator, the depth counter increments. Increase `max_depth` when you intentionally nest more than eight layers, and decrease it when authoring short, bounded expansions so validation catches accidental loops sooner.

Hybrid steps may themselves invoke templates. When doing so, propagate the `max_depth` setting into nested configs to keep the limit consistent across the entire sentence graph:

```gdscript
{
    "strategy": "template",
    "max_depth": 6,
    "template_string": "[mission_blurb]",
    "sub_generators": {
        "mission_blurb": {
            "strategy": "template",
            "max_depth": 6,
            "template_string": "[faction_header] [mission_hook]"
        }
    }
}
```

## RNG stream and seeding considerations

Every `NameGenerator.generate` request must include a `seed`. `TemplateStrategy` derives child seeds automatically by combining the parent seed, token name, and invocation index (`parent::token::occurrence`). `HybridStrategy` follows a similar cascade, deriving child RNG streams per step alias.

Guidelines:

- Set an explicit top-level `seed` so the entire sentence tree is reproducible.
- Override `seed` inside a sub-generator only when you need cross-template stability (e.g. two different templates that must produce matching `$faction` names).
- Use `rng_stream` when you want multiple top-level configs to share a deterministic stream without reusing the same seed text.

DebugRNG reports each derived stream, making it easier to audit how seeds are consumed across hybrid-template pipelines.

## End-to-end examples

The following snippets illustrate how to wire the new narrative datasets into deterministic pipelines.

### Skill description sentence (Template inside Hybrid)

1. **Datasets**
   - `res://data/wordlists/skills/skill_verbs.tres` – action verbs (`"amplify"`, `"channel"`, ...).
   - `res://data/wordlists/skills/skill_themes.tres` – thematic nouns (`"storms"`, `"sigils"`, ...).
   - `res://data/wordlists/skills/skill_payloads.tres` – effect blurbs (`"to mend allies"`, `"to unravel wards"`, ...).

2. **Configuration**

```gdscript
var config := {
    "strategy": "hybrid",
    "seed": "skill_sentence_v1",
    "steps": [
        {
            "strategy": "wordlist",
            "seed": "skill_sentence_v1::verb",
            "wordlist_paths": ["res://data/wordlists/skills/skill_verbs.tres"],
            "store_as": "skill_verb",
        },
        {
            "strategy": "wordlist",
            "seed": "skill_sentence_v1::theme",
            "wordlist_paths": ["res://data/wordlists/skills/skill_themes.tres"],
            "store_as": "skill_theme",
        },
        {
            "strategy": "template",
            "seed": "skill_sentence_v1::blurb",
            "template_string": "[skill_sentence]",
            "sub_generators": {
                "skill_sentence": {
                    "strategy": "template",
                    "template_string": "The $skill_verb of $skill_theme [skill_payload]",
                    "sub_generators": {
                        "skill_payload": {
                            "strategy": "wordlist",
                            "seed": "skill_sentence_v1::payload",
                            "wordlist_paths": ["res://data/wordlists/skills/skill_payloads.tres"],
                        }
                    }
                }
            }
        }
    ],
    "template": "$skill_sentence",
}
```

3. **Usage**

```gdscript
var sentence := NameGenerator.generate(config)
# => "The channel of sigils to mend allies"
```

Re-running the pipeline with the same top-level seed reproduces the exact sentence because each step and nested template shares the deterministic `skill_sentence_v1` prefix.

### Faction mission blurb (Hybrid with nested templates)

1. **Datasets**
   - `res://data/wordlists/factions/faction_titles.tres` – faction names (`"Skyward Accord"`, ...).
   - `res://data/wordlists/factions/mission_verbs.tres` – verbs suited for mission hooks.
   - `res://data/wordlists/factions/mission_targets.tres` – objectives or targets.
   - `res://data/wordlists/factions/mission_twists.tres` – optional twists or complications.

2. **Configuration**

```gdscript
var mission_config := {
    "strategy": "hybrid",
    "seed": "faction_mission_demo",
    "steps": [
        {
            "strategy": "wordlist",
            "seed": "faction_mission_demo::faction",
            "wordlist_paths": ["res://data/wordlists/factions/faction_titles.tres"],
            "store_as": "faction",
        },
        {
            "strategy": "template",
            "seed": "faction_mission_demo::mission",
            "max_depth": 5,
            "template_string": "[mission_body]",
            "sub_generators": {
                "mission_body": {
                    "strategy": "template",
                    "template_string": "$faction must [mission_action]",
                    "sub_generators": {
                        "mission_action": {
                            "strategy": "template",
                            "template_string": "[mission_verb] [mission_target] [mission_twist]",
                            "sub_generators": {
                                "mission_verb": {
                                    "strategy": "wordlist",
                                    "seed": "faction_mission_demo::verb",
                                    "wordlist_paths": ["res://data/wordlists/factions/mission_verbs.tres"],
                                },
                                "mission_target": {
                                    "strategy": "wordlist",
                                    "seed": "faction_mission_demo::target",
                                    "wordlist_paths": ["res://data/wordlists/factions/mission_targets.tres"],
                                },
                                "mission_twist": {
                                    "strategy": "wordlist",
                                    "seed": "faction_mission_demo::twist",
                                    "wordlist_paths": ["res://data/wordlists/factions/mission_twists.tres"],
                                }
                            }
                        }
                    }
                }
            }
        }
    ],
    "template": "$mission",
}
```

3. **Usage**

```gdscript
var mission := NameGenerator.generate(mission_config)
# => "Skyward Accord must safeguard the astral vault while traitors whisper within"
```

Each nested seed shares the `faction_mission_demo` prefix, so any change to the alias names or token order remains reproducible and easy to debug.

## Validation workflow

After updating template or hybrid configurations, run the regression suite to ensure no deterministic guarantees regressed:

```bash
godot --headless --script res://tests/run_all_tests.gd
```

The command executes both strategy-level tests and RNGProcessor coverage, providing confidence that sentence changes still align with the engine’s deterministic contracts.
