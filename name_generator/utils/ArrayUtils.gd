## Utility helpers for deterministic array selection.
##
## The functions in this module intentionally avoid touching Godot's global RNG
## state. Callers must supply an explicit [RandomNumberGenerator] so reproducible
## results can be achieved across gameplay, tooling, and automated tests.
class_name ArrayUtils

static var _last_assertion: Dictionary = {}
static var _last_fallback: Dictionary = {}

static func assert_not_empty(collection: Variant, context: String = "Collection") -> void:
    var is_empty := false
    if collection == null:
        is_empty = true
    elif collection is Array:
        is_empty = (collection as Array).is_empty()
    elif collection is Dictionary:
        is_empty = (collection as Dictionary).is_empty()
    elif collection is Object:
        if collection.has_method("is_empty"):
            is_empty = bool(collection.call("is_empty"))
        elif collection.has_method("size"):
            is_empty = int(collection.call("size")) == 0
    else:
        is_empty = false

    if is_empty:
        var message: String = "%s must not be empty." % context
        _record_assertion(message)
        push_error(message)
        assert(false, message)

static func pick_uniform(items: Array, rng: RandomNumberGenerator) -> Variant:
    assert_not_empty(items, "Items")
    if items.size() == 1:
        return items[0]
    var index: int = rng.randi_range(0, items.size() - 1)
    return items[index]

static func pick_random_deterministic(items: Array, rng: RandomNumberGenerator) -> Variant:
    return pick_uniform(items, rng)

static func pick_weighted(entries: Array, rng: RandomNumberGenerator) -> Variant:
    assert_not_empty(entries, "Weighted entries")
    var normalised: Array[Dictionary] = []
    var total_weight: float = 0.0

    for entry in entries:
        var parsed: Dictionary = _parse_weighted_entry(entry)
        total_weight += parsed["weight"]
        normalised.append(parsed)

    if total_weight <= 0.0:
        var message: String = "Weighted entries must have a combined positive weight."
        _record_assertion(message)
        push_error(message)
        assert(false, message)

    var roll: float = rng.randf() * total_weight
    var cumulative: float = 0.0
    for entry in normalised:
        cumulative += entry["weight"]
        if roll <= cumulative:
            return entry["value"]

    return normalised.back()["value"]

static func pick_weighted_random_deterministic(entries: Array, rng: RandomNumberGenerator) -> Variant:
    return pick_weighted(entries, rng)

static func handle_empty_with_fallback(
    collection: Array,
    fallback: Variant = null,
    context: String = "Collection",
) -> Dictionary:
    var state: Dictionary = {
        "was_empty": false,
        "value": null,
    }

    _last_fallback.clear()

    if collection != null and not collection.is_empty():
        return state

    state["was_empty"] = true
    var message: String = "%s must not be empty." % context

    if fallback == null:
        _record_assertion(message)
        _record_fallback(context, null, false, 0, true)
        push_error(message)
        assert(false, message)
        return state

    if fallback is Callable and not fallback.is_null():
        var fallback_value: Variant = fallback.call()
        state["value"] = fallback_value
        _record_fallback(context, fallback_value, true, 1, true)
    else:
        state["value"] = fallback
        _record_fallback(context, state["value"], false, 0, true)

    return state

static func _parse_weighted_entry(entry: Variant) -> Dictionary:
    var value: Variant = null
    var weight: Variant = null

    if entry is Dictionary:
        var dictionary := entry as Dictionary
        if dictionary.has("value"):
            value = dictionary["value"]
        elif dictionary.has("item"):
            value = dictionary["item"]
        elif dictionary.has("entry"):
            value = dictionary["entry"]

        if dictionary.has("weight"):
            weight = dictionary["weight"]
        elif dictionary.has("chance"):
            weight = dictionary["chance"]
    elif entry is Array and entry.size() >= 2:
        value = entry[0]
        weight = entry[1]

    if weight == null:
        var message: String = "Weighted entry %s is missing a weight." % [entry]
        _record_assertion(message)
        push_error(message)
        assert(false, message)

    var weight_number: float = float(weight)
    if weight_number < 0.0:
        var message: String = "Weighted entry %s cannot use a negative weight." % [entry]
        _record_assertion(message)
        push_error(message)
        assert(false, message)

    return {
        "value": value,
        "weight": weight_number,
    }

static func clear_last_assertion() -> void:
    _last_assertion.clear()

static func get_last_assertion() -> Dictionary:
    return _last_assertion.duplicate(true)

static func clear_last_fallback() -> void:
    _last_fallback.clear()

static func get_last_fallback() -> Dictionary:
    return _last_fallback.duplicate(true)

static func _record_assertion(message: String) -> void:
    _last_assertion = {
        "message": message,
        "timestamp": Time.get_ticks_usec(),
    }

static func _record_fallback(context: String, value: Variant, via_callable: bool, call_count: int, was_empty: bool) -> void:
    _last_fallback = {
        "context": context,
        "value": value,
        "via_callable": via_callable,
        "call_count": call_count,
        "was_empty": was_empty,
        "timestamp": Time.get_ticks_usec(),
    }
