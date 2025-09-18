@tool
extends Resource
class_name WordListResource

## Resource that exposes curated word collections for the WordlistStrategy.
## Designers can author either simple uniform lists or provide explicit
## weighting. The helper methods normalise the data for runtime code so
## strategies do not need to worry about the specific authoring format.

@export_group("Entries")
@export var entries: PackedStringArray = PackedStringArray()
@export var weights: PackedFloat32Array = PackedFloat32Array()
@export var weighted_entries: Array[Dictionary] = []

@export_group("Metadata")
@export var locale: String = ""
@export var domain: String = ""

func has_weight_data() -> bool:
    if not weighted_entries.is_empty():
        return true
    return not weights.is_empty() and weights.size() == entries.size()

func get_uniform_entries() -> Array:
    var result: Array[String] = []
    result.assign(entries)
    return result

func get_weighted_entries() -> Array:
    if not weighted_entries.is_empty():
        var result: Array[Dictionary] = []
        for entry in weighted_entries:
            if typeof(entry) == TYPE_DICTIONARY and entry.has("value"):
                var value: Variant = entry["value"]
                var weight_value: float = float(entry.get("weight", 1.0))
                if weight_value > 0.0:
                    result.append({"value": value, "weight": weight_value})
        if not result.is_empty():
            return result

    if not weights.is_empty() and weights.size() == entries.size():
        var result: Array[Dictionary] = []
        for index in range(entries.size()):
            var weight_value: float = float(weights[index])
            if weight_value <= 0.0:
                continue
            result.append({
                "value": entries[index],
                "weight": weight_value,
            })
        if not result.is_empty():
            return result

    var fallback: Array[Dictionary] = []
    for entry in entries:
        fallback.append({"value": entry, "weight": 1.0})
    return fallback
