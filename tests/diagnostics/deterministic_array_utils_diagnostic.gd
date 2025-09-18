extends RefCounted

const ArrayUtils := preload("res://name_generator/utils/ArrayUtils.gd")
const ERROR_CAPTURE_CHANNELS := [
    StringName("error"),
    StringName("user_error"),
    StringName("script_error"),
]

var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _checks.clear()

    _record("assert_not_empty_rejects_empty_inputs", func(): return _test_assert_not_empty_rejects_empty_inputs())
    _record("assert_not_empty_accepts_non_empty", func(): return _test_assert_not_empty_accepts_non_empty())
    _record("pick_uniform_produces_deterministic_sequences", func(): return _test_pick_uniform_determinism())
    _record("pick_weighted_supports_dictionary_entries", func(): return _test_pick_weighted_with_dictionaries())
    _record("pick_weighted_supports_array_entries", func(): return _test_pick_weighted_with_arrays())
    _record("parse_weighted_entry_validates_payloads", func(): return _test_parse_weighted_entry_behaviour())
    _record("handle_empty_with_fallback_uses_callable", func(): return _test_handle_empty_with_fallback_callable())
    _record("handle_empty_without_fallback_asserts", func(): return _test_handle_empty_without_fallback_asserts())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    return {
        "id": "deterministic_array_utils",
        "name": "Deterministic ArrayUtils guardrail diagnostic",
        "total": _checks.size(),
        "passed": _checks.size() - failures.size(),
        "failed": failures.size(),
        "failures": failures.duplicate(true),
    }

func _record(name: String, callable: Callable) -> void:
    var outcome = callable.call()
    var success := outcome == null
    _checks.append({
        "name": name,
        "success": success,
        "message": "" if success else String(outcome),
    })

func _test_assert_not_empty_rejects_empty_inputs() -> Variant:
    var array_capture := _capture_assert_failure(func():
        ArrayUtils.assert_not_empty([], "Empty array")
        return null
    )
    if not array_capture.get("asserted", false):
        return "Empty arrays should trigger assert_not_empty()."
    if array_capture.get("message", "").find("Empty array must not be empty") == -1:
        return "assert_not_empty() message should include the provided context."

    var dict_capture := _capture_assert_failure(func():
        ArrayUtils.assert_not_empty({}, "Empty dictionary")
        return null
    )
    if not dict_capture.get("asserted", false):
        return "Empty dictionaries should trigger assert_not_empty()."

    return null

func _test_assert_not_empty_accepts_non_empty() -> Variant:
    var array_capture := _capture_assert_failure(func():
        ArrayUtils.assert_not_empty(["value"], "Array input")
        return null
    )
    if array_capture.get("asserted", false):
        return "Non-empty arrays should not assert."

    var dict_capture := _capture_assert_failure(func():
        ArrayUtils.assert_not_empty({"key": "value"}, "Dictionary input")
        return null
    )
    if dict_capture.get("asserted", false):
        return "Non-empty dictionaries should not assert."

    return null

func _test_pick_uniform_determinism() -> Variant:
    var values := ["alpha", "beta", "gamma", "delta"]

    var first_rng := RandomNumberGenerator.new()
    first_rng.seed = 31415
    var second_rng := RandomNumberGenerator.new()
    second_rng.seed = 31415

    var first_sequence := []
    var second_sequence := []
    for _i in range(8):
        first_sequence.append(ArrayUtils.pick_uniform(values, first_rng))
        second_sequence.append(ArrayUtils.pick_uniform(values, second_rng))

    if first_sequence != second_sequence:
        return "pick_uniform should be deterministic when RNG seeds match."

    var empty_capture := _capture_assert_failure(func():
        ArrayUtils.pick_uniform([], first_rng)
        return null
    )
    if not empty_capture.get("asserted", false):
        return "pick_uniform should assert on empty arrays."
    if empty_capture.get("message", "").find("Items must not be empty") == -1:
        return "pick_uniform assertion should mention the 'Items' context."

    return null

func _test_pick_weighted_with_dictionaries() -> Variant:
    var entries := [
        {"value": "copper", "weight": 1.0},
        {"item": "silver", "weight": 2.0},
        {"entry": "gold", "chance": 3.5},
    ]

    var first_rng := RandomNumberGenerator.new()
    first_rng.seed = 27182
    var second_rng := RandomNumberGenerator.new()
    second_rng.seed = 27182

    var first_sequence := []
    var second_sequence := []
    for _i in range(10):
        first_sequence.append(ArrayUtils.pick_weighted(entries, first_rng))
        second_sequence.append(ArrayUtils.pick_weighted(entries, second_rng))

    if first_sequence != second_sequence:
        return "Dictionary payloads should yield deterministic weighted selections with identical seeds."

    return null

func _test_pick_weighted_with_arrays() -> Variant:
    var entries := [
        ["ember", 0.5],
        ["frost", 1.5],
        ["gale", 2.5],
    ]

    var first_rng := RandomNumberGenerator.new()
    first_rng.seed = 112358
    var second_rng := RandomNumberGenerator.new()
    second_rng.seed = 112358

    var first_sequence := []
    var second_sequence := []
    for _i in range(10):
        first_sequence.append(ArrayUtils.pick_weighted(entries, first_rng))
        second_sequence.append(ArrayUtils.pick_weighted(entries, second_rng))

    if first_sequence != second_sequence:
        return "Array payloads should yield deterministic weighted selections with identical seeds."

    return null

func _test_parse_weighted_entry_behaviour() -> Variant:
    var array_entry := ArrayUtils._parse_weighted_entry(["onyx", 4])
    if array_entry.get("value", "") != "onyx":
        return "Array payload should preserve the first element as the value."
    if not is_equal_approx(array_entry.get("weight", 0.0), 4.0):
        return "Array payload should coerce the weight to a float."

    var dictionary_entry := ArrayUtils._parse_weighted_entry({"value": "opal", "weight": 2.25})
    if dictionary_entry.get("value", "") != "opal":
        return "Dictionary payload should respect the 'value' key."
    if not is_equal_approx(dictionary_entry.get("weight", 0.0), 2.25):
        return "Dictionary payload should respect the numeric weight."

    var missing_weight_capture := _capture_assert_failure(func():
        ArrayUtils._parse_weighted_entry({"value": "quartz"})
        return null
    )
    if not missing_weight_capture.get("asserted", false):
        return "Entries missing weights should assert."
    if missing_weight_capture.get("message", "").find("missing a weight") == -1:
        return "Missing weight assertion message should mention the issue."

    var negative_weight_capture := _capture_assert_failure(func():
        ArrayUtils._parse_weighted_entry(["ruby", -3])
        return null
    )
    if not negative_weight_capture.get("asserted", false):
        return "Negative weights should assert."
    if negative_weight_capture.get("message", "").find("negative weight") == -1:
        return "Negative weight assertion message should highlight the invalid value."

    return null

func _test_handle_empty_with_fallback_callable() -> Variant:
    var invocations := 0
    var state_capture := _capture_assert_failure(func():
        return ArrayUtils.handle_empty_with_fallback([], func():
            invocations += 1
            return "fallback"
        , "Fallback")
    )

    if state_capture.get("asserted", false):
        return "Supplying a fallback should avoid assertions."

    var state := state_capture.get("result", {})
    if not (state is Dictionary):
        return "handle_empty_with_fallback should return a dictionary state."
    if not state.get("was_empty", false):
        return "State should report the original collection as empty."
    if state.get("value", "") != "fallback":
        return "Fallback callable should populate the state value."

    var fallback_record := ArrayUtils.get_last_fallback()
    if fallback_record.get("call_count", 0) != 1:
        return "Fallback callable should execute exactly once."
    if fallback_record.get("via_callable", false) == false:
        return "Fallback record should note callable usage."
    if fallback_record.get("value", "") != "fallback":
        return "Fallback record should capture the returned value."

    var populated := ArrayUtils.handle_empty_with_fallback([1, 2, 3], "unused", "Populated")
    if populated.get("was_empty", false):
        return "Non-empty collections must not set was_empty to true."
    if populated.get("value", null) != null:
        return "Non-empty collections should leave the value unset."

    return null

func _test_handle_empty_without_fallback_asserts() -> Variant:
    var state: Dictionary = {}
    var capture := _capture_assert_failure(func():
        state = ArrayUtils.handle_empty_with_fallback([], null, "Missing fallback")
        return state
    )

    if not capture.get("asserted", false):
        return "Missing fallback should assert."
    if capture.get("message", "").find("Missing fallback must not be empty") == -1:
        return "Assertion message should include the provided context."
    var fallback_record := ArrayUtils.get_last_fallback()
    if fallback_record.get("was_empty", false) == false:
        return "Fallback record should indicate the collection was empty."
    if fallback_record.get("value", "sentinel") != null:
        return "Fallback record should retain a null value when no fallback is provided."
    if fallback_record.get("call_count", 1) != 0:
        return "Fallback record should show no callable execution when fallback is missing."

    return null

func _capture_assert_failure(callable: Callable) -> Dictionary:
    var previous_print_setting := Engine.print_error_messages
    Engine.print_error_messages = false

    var info := {
        "asserted": false,
        "message": "",
        "result": null,
    }

    ArrayUtils.clear_last_assertion()
    ArrayUtils.clear_last_fallback()

    var capture_callable := func(message: String, data: Array) -> bool:
        if not info["asserted"]:
            info["asserted"] = true
            info["message"] = String(message).strip_edges()
        return true

    var registered: Array[StringName] = []
    if EngineDebugger != null:
        for name in ERROR_CAPTURE_CHANNELS:
            if EngineDebugger.has_capture(name):
                continue
            EngineDebugger.register_message_capture(name, capture_callable)
            registered.append(name)

    info["result"] = callable.call()

    if not info["asserted"]:
        var last_assertion := ArrayUtils.get_last_assertion()
        if not last_assertion.is_empty():
            info["asserted"] = true
            info["message"] = String(last_assertion.get("message", "")).strip_edges()

    if EngineDebugger != null:
        for name in registered:
            EngineDebugger.unregister_message_capture(name)

    Engine.print_error_messages = previous_print_setting

    return info
