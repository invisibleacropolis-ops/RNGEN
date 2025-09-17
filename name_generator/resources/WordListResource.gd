@tool
extends Resource
class_name WordListResource

## WordListResource provides simple and weighted word collections for the name generator.
## Designers can configure either `entries` for equal-probability names or `weighted_entries`
## for fine-grained control over selection probability.

## Simple list of entries used when each name should have equal probability of being chosen.
## Populate this when weighting is not required. Leave empty when using `weighted_entries`.
@export_placeholder("Example: Alice, Bob, Carol")
@export var entries: PackedStringArray = PackedStringArray()

## Weighted entries allow assigning relative selection weights to each value.
## Each dictionary entry should contain a `value` (String) and a `weight` (float > 0).
## Use this list instead of `entries` when specific probability distribution is needed.
@export_placeholder('Example: [{"value": "Alice", "weight": 1.0}]')
@export var weighted_entries: Array[Dictionary] = []

## Utility method to determine if any weighted data has been provided.
func has_weighted_entries() -> bool:
    return not weighted_entries.is_empty()
