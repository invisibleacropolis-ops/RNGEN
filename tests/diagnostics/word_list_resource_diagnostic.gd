extends RefCounted

const WordListResource := preload("res://name_generator/resources/WordListResource.gd")

var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _checks.clear()

    _record("weighted_arrays_positive", func(): return _test_weighted_arrays_positive())
    _record("filters_non_positive_weights", func(): return _test_filters_non_positive_weights())
    _record("dictionary_weighted_entries_override", func(): return _test_dictionary_weighted_entries_override())
    _record("invalid_dictionary_weights_fall_back", func(): return _test_invalid_dictionary_weights_fall_back())
    _record("missing_weights_fall_back", func(): return _test_missing_weights_fall_back())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    return {
        "id": "word_list_resource",
        "name": "WordListResource deterministic helper diagnostic",
        "total": _checks.size(),
        "passed": _checks.size() - failures.size(),
        "failed": failures.size(),
        "failures": failures.duplicate(true),
    }

func _record(name: String, callable: Callable) -> void:
    var result = callable.call()
    var success := result == null
    _checks.append({
        "name": name,
        "success": success,
        "message": "" if success else String(result),
    })

func _test_weighted_arrays_positive() -> Variant:
    var resource := WordListResource.new()
    resource.entries = PackedStringArray(["ash", "birch", "cedar"])
    resource.weights = PackedFloat32Array([1.0, 2.0, 3.0])

    if not resource.has_weight_data():
        return "Resource should report weight data when weights align with entries."

    var uniform := resource.get_uniform_entries()
    if uniform != ["ash", "birch", "cedar"]:
        return "Uniform entries must mirror the declared entries."

    var weighted := resource.get_weighted_entries()
    var expected := [
        {"value": "ash", "weight": 1.0},
        {"value": "birch", "weight": 2.0},
        {"value": "cedar", "weight": 3.0},
    ]
    if weighted != expected:
        return "Weighted entries should map each value to its weight; received %s" % [weighted]

    return null

func _test_filters_non_positive_weights() -> Variant:
    var resource := WordListResource.new()
    resource.entries = PackedStringArray(["ember", "frost", "gale", "hail"])
    resource.weights = PackedFloat32Array([0.0, -2.5, 2.5, 1.0])

    if not resource.has_weight_data():
        return "Resource should detect weight data even if some weights are filtered."

    var weighted := resource.get_weighted_entries()
    var expected := [
        {"value": "gale", "weight": 2.5},
        {"value": "hail", "weight": 1.0},
    ]
    if weighted != expected:
        return "Non-positive weights must be removed from the weighted list; received %s" % [weighted]

    return null

func _test_dictionary_weighted_entries_override() -> Variant:
    var resource := WordListResource.new()
    resource.entries = PackedStringArray(["onyx", "pearl", "quartz"])
    resource.weights = PackedFloat32Array([5.0, 5.0, 5.0])
    resource.weighted_entries = [
        {"value": "onyx", "weight": 4.0},
        {"value": "pearl", "weight": 0.0},
        {"value": "quartz"},
        {"weight": 3.0},
        "invalid",
    ]

    if not resource.has_weight_data():
        return "Resource should report weight data when weighted_entries are provided."

    var weighted := resource.get_weighted_entries()
    var expected := [
        {"value": "onyx", "weight": 4.0},
    ]
    if weighted != expected:
        return "Weighted entries should prefer dictionary authoring with validation; received %s" % [weighted]

    return null

func _test_invalid_dictionary_weights_fall_back() -> Variant:
    var resource := WordListResource.new()
    resource.entries = PackedStringArray(["red", "green", "blue"])
    resource.weights = PackedFloat32Array([10.0])
    resource.weighted_entries = [
        {"value": "red", "weight": 0.0},
        {"value": "green", "weight": -1.0},
        {"weight": 2.0},
        "invalid",
    ]

    if not resource.has_weight_data():
        return "Resource should still report weight data when weighted_entries exist."

    var weighted := resource.get_weighted_entries()
    var expected := [
        {"value": "red", "weight": 1.0},
        {"value": "green", "weight": 1.0},
        {"value": "blue", "weight": 1.0},
    ]
    if weighted != expected:
        return "Invalid weighted entries should fall back to uniform weights; received %s" % [weighted]

    return null

func _test_missing_weights_fall_back() -> Variant:
    var resource := WordListResource.new()
    resource.entries = PackedStringArray(["alpha", "beta"])

    if resource.has_weight_data():
        return "Resource should report missing weight data when none is provided."

    var weighted := resource.get_weighted_entries()
    var expected := [
        {"value": "alpha", "weight": 1.0},
        {"value": "beta", "weight": 1.0},
    ]
    if weighted != expected:
        return "Absent weights should fall back to uniform weighting; received %s" % [weighted]

    return null
