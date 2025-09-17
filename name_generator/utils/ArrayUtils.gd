class_name ArrayUtils

"""
Utility helpers for deterministic array selection.

This module intentionally never reaches out to Godot's global random number
functions.  Every operation that requires randomness expects a
``RandomNumberGenerator`` instance to be supplied by the caller so tests and
save/load flows can provide their own deterministic seeds.
"""

static func assert_not_empty(collection: Array, context: String = "Collection") -> void:
    """
    Ensure that ``collection`` contains at least one element.

    The helpers in this file intentionally avoid any calls to global
    randomness APIs so the caller has full control over the provided
    ``RandomNumberGenerator``.
    """
    if collection == null or collection.is_empty():
        var message := "%s must not be empty." % context
        push_error(message)
        assert(false, message)


static func handle_empty_with_fallback(
    collection: Array,
    fallback := null,
    context: String = "Collection",
) -> Dictionary:
    """
    Handle empty collections by optionally falling back to ``fallback``.

    The return value communicates whether the fallback was used so callers can
    avoid ambiguous ``null`` checks.

    Returns a dictionary with two keys:
    - ``was_empty``: ``true`` if ``collection`` was empty.
    - ``value``: The fallback value (when provided) or ``null``.

    The helper must remain free of global randomness.  Only the caller decides
    how to generate fallback content, ensuring deterministic behaviour in tests
    and save/load scenarios.
    """
    var state := {
        "was_empty": false,
        "value": null,
    }

    if collection != null and not collection.is_empty():
        return state

    state["was_empty"] = true
    var message := "%s must not be empty." % context

    if fallback == null:
        push_error(message)
        assert(false, message)
        return state

    if fallback is Callable and not fallback.is_null():
        state["value"] = fallback.call()
    else:
        state["value"] = fallback

    return state


static func pick_random_deterministic(items: Array, rng: RandomNumberGenerator) -> Variant:
    """
    Pick a random element from ``items`` using the provided ``rng`` only.

    The helper never touches ``RandomNumberGenerator``'s global state so the
    caller retains deterministic control.
    """
    assert_not_empty(items, "Items")

    if items.size() == 1:
        return items[0]

    # Use the caller-supplied RNG exclusively to stay deterministic.
    var index := rng.randi_range(0, items.size() - 1)
    return items[index]


static func pick_weighted_random_deterministic(entries: Array, rng: RandomNumberGenerator) -> Variant:
    """
    Pick a weighted entry from ``entries`` using the supplied ``rng`` only.

    Each entry can be either a dictionary or a two-element array:
    - ``{"value": value, "weight": number}``
    - ``{"item": value, "weight": number}``
    - ``[value, weight]``

    The function intentionally avoids any reliance on global randomness to keep
    simulations deterministic when the caller provides a seeded RNG.
    """
    assert_not_empty(entries, "Weighted entries")

    var normalized_entries: Array = []
    var total_weight := 0.0

    for entry in entries:
        var parsed := _parse_weighted_entry(entry)
        total_weight += parsed["weight"]
        normalized_entries.append(parsed)

    if total_weight <= 0.0:
        var message := "Weighted entries must have a combined positive weight."
        push_error(message)
        assert(false, message)

    # Roll against the total weight using only the provided RNG.
    var roll := rng.randf() * total_weight
    var cumulative := 0.0

    for entry in normalized_entries:
        cumulative += entry["weight"]
        if roll <= cumulative:
            return entry["value"]

    return normalized_entries.back()["value"]


static func _parse_weighted_entry(entry: Variant) -> Dictionary:
    """
    Convert ``entry`` into a dictionary with ``value`` and ``weight`` keys.

    The helper only performs deterministic validation and does not use any
    randomness.
    """
    var value := null
    var weight := null

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
        var message := "Weighted entry %s is missing a weight." % [entry]
        push_error(message)
        assert(false, message)

    var weight_number := float(weight)
    if weight_number < 0.0:
        var message := "Weighted entry %s cannot use a negative weight." % [entry]
        push_error(message)
        assert(false, message)

    return {
        "value": value,
        "weight": weight_number,
    }
