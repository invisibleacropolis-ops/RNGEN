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
