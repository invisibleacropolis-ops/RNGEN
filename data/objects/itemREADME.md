# Object Names Data

This folder holds themed vocabularies for equipment, curios, relics, and other inanimate loot. Populate it with reusable building blocks so new generators can mix and match consistent terminology.

## Item family guides

### Weapons
- **Core wordlists**: `materials` for blade/haft metals and woods, `modifiers` for edge qualities, and `weapon_cores` for base nouns like "sword" or "glaive".
- **Weighted entry example**: give rare alloys extra gravity, e.g. `meteor_iron: 2` vs. `steel: 5` to keep mundane outputs common while letting dramatic variants surface occasionally.
- **Usage tips**: pair with action descriptors (`$modifier $material $weapon_core`) for straightforward loot tables. Promote Hybrid pipelines when chaining combat effects (e.g. first pick `$material`, then call an effect list and assemble with a template).

### Armor & apparel
- **Core wordlists**: `materials`, `modifiers`, `armor_cores` (helms, cuirasses, cloaks), plus optional `adornments` for trim.
- **Weighted entry example**: bias ceremonial items lower, e.g. `ceremonial: 1` versus `battleworn: 4` so battle gear dominates random drops.
- **Usage tips**: simple template combos like `$modifier $armor_core` shine for quick results; escalate to Hybrid when you need tiered assembly such as selecting a base garment, then layering insignia or enchantments.

### Arcane curios & relics
- **Core wordlists**: `materials` (crystals, runes, bones), `modifiers` (eldritch, radiant), `relic_cores` (orb, focus, idol), and `effects` for magical payloads.
- **Weighted entry example**: weight `cursed: 3`, `blessed: 2`, `neutral: 6` inside `effects` to keep doomful boons present without overwhelming mundane artifacts.
- **Usage tips**: Hybrid pipelines excel for spell-driven phrasing (`$material $relic_core of $effect`). Reserve direct wordlist templates for flavor text or inventory summaries.

### Consumables & supplies
- **Core wordlists**: `materials` (herbs, minerals), `modifiers`, `supply_cores` (tonic, salve, ration), and optional `effects` describing the buff.
- **Weighted entry example**: prefer everyday ingredients (`mint_leaf: 6`) over exotic ones (`phoenix_ash: 1`) so upgrades feel special.
- **Usage tips**: start with simple combinations (`$modifier $supply_core`) when readability matters; reach for Hybrid configurations to append usage notes or conditional bonuses.

### Technology & artifacts
- **Core wordlists**: `materials` (alloys, circuitry), `modifiers` (prototype, rugged), `artifact_cores` (relay, core, lattice), and `effects` for energy signatures.
- **Weighted entry example**: differentiate power tiers with weights such as `quantum: 1`, `plasma: 3`, `arc: 5` within the `effects` list.
- **Usage tips**: rely on Hybrid setups to splice together component names, serial numbers, and power descriptors while TemplateStrategy remains ideal for single-line catalog entries.

## Choosing your generation pipeline
- **Simple wordlist templates** keep maintenance low and work best when the result is a short noun phrase. Reach for combos like `$modifier $material $item_core` whenever the lists are rich and you just need quick variety.
- **Hybrid pipelines** (`steps` + optional `template`) shine when the name depends on staged decisions or needs interpolation from multiple sources (e.g. pick material → select item type → slot in an effect to yield "Auric Glaive of Drowning"). Use them for multi-sentence blurbs or when data must be reused later in the generation process.
- For sentence-style or paragraph outputs, use the `template` key available to both TemplateStrategy and HybridStrategy. It provides full-string control ("Forged from $material, this $item_core hums with $effect"), keeping formatting consistent across locales.

## Starter templates

Reference the assets in `data/objects/templates/` when you need an immediate
resource scaffold:

- `object_wordlist_template.tres` stores a small equipment-flavoured
  `WordListResource` with weighted entries.
- `object_syllable_template.tres` shows how to distribute fragments across the
  `SyllableSetResource` arrays while keeping the middle optional.
- `object_markov_template.tres` is a `MarkovModelResource` configured with the
  modern transition layout so new models can plug directly into the generator.

Copy the relevant template, rename it, and replace the placeholder entries with
your item vocabulary before committing the resource.

| Template filename | Contents | Reuse guidance |
| --- | --- | --- |
| `weapon_materials_template.tres` | Weighted sample of mundane through legendary alloys (steel, meteoric iron, obsidian, starfire alloy). | Start with TemplateStrategy for quick `$modifier $material $weapon_core` pairings; HybridStrategy can reference it in a `steps` chain when branching into effect-driven loot. |
| `weapon_modifiers_template.tres` | Uniform list of tonal adjectives (keen, ancient, ceremonial, whispering). | Works as-is for TemplateStrategy slots; reuse in Hybrid setups when combining with conditional templates or follow-up effect picks. |
| `weapon_cores_template.tres` | Uniform base noun list (blade, spear, glaive, scythe). | Ideal for both TemplateStrategy and HybridStrategy as the structural noun anchor before embellishments. |
| `weapon_effects_template.tres` | Uniform suffix phrases (of embers, of echoes, of tides, of dawns). | Drop directly into TemplateStrategy endings or pull in during Hybrid finalisation steps when effects depend on earlier choices. |

## Quality assurance checklist
- Run the dataset inspector to confirm new `.tres` resources appear with the expected entry counts:
  ```
  godot --headless --path . --script res://name_generator/tools/dataset_inspector.gd
  ```
- Execute the regression suites (`pytest` equivalents live in `tests/`) so Hybrid and template pipelines stay deterministic:
  ```
  godot --headless --path . --script res://tests/run_generator_tests.gd
  godot --headless --path . --script res://tests/run_diagnostics_tests.gd
  ```
- If a new resource introduces additional wordlists, update or add focused tests so failures surface through CI before designers hit broken content.
