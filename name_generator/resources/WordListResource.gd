
## Resource that encapsulates the list of candidate words a strategy can pick
## from.  Each entry can optionally define a weight to bias the selection.
##
## The resource is intentionally lightweight so it can be easily authored in
## the Godot inspector.  Designers can provide a PackedStringArray of entries
## and, when weighted selection is desired, a parallel PackedFloat32Array.
extends Resource
class_name WordListResource

## Textual candidates that can be combined into generated names.
@export var entries: PackedStringArray = PackedStringArray()

## Optional weights that map 1:1 to ``entries``.  When left empty, selection is
## treated as uniform.
@export var weights: PackedFloat32Array = PackedFloat32Array()

## Returns a standard ``Array`` copy of the configured entries.  A copy is used
## so callers can safely mutate the result without affecting the resource.
func get_entries() -> Array:
    return entries.to_array()

## Returns a standard ``Array`` view of the configured weights when valid.
## The method performs validation to ensure we never emit mismatched arrays.
func get_weights() -> Array:
    if weights.is_empty() or weights.size() != entries.size():
        return []
    return weights.to_array()

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

