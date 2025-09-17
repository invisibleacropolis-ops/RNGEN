extends RefCounted

const MarkovModelResource := preload("res://name_generator/resources/MarkovModelResource.gd")

var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _checks.clear()

    _record("states_and_end_tokens", func(): return _test_state_and_end_token_population())
    _record("transition_block_filtering", func(): return _test_transition_block_filtering())
    _record("token_temperature_defaults", func(): return _test_token_temperature_defaults())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    return {
        "id": "markov_model_resource",
        "name": "MarkovModelResource data integrity diagnostic",
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

func _test_state_and_end_token_population() -> Variant:
    var model := MarkovModelResource.new()
    var defined_states := PackedStringArray(["alpha", "beta", "gamma"])
    var defined_end_tokens := PackedStringArray(["<END>", "!"])
    var defined_transitions := {
        "alpha": [{"token": "beta", "weight": 1.0}],
        "beta": [{"token": "gamma", "weight": 1.0}],
        "gamma": [{"token": "<END>", "weight": 1.0}],
    }

    model.states = defined_states
    model.end_tokens = defined_end_tokens
    model.transitions = defined_transitions

    if model.states != defined_states:
        return "Assigned states should be preserved on the resource."

    if model.end_tokens != defined_end_tokens:
        return "Assigned end tokens should be preserved on the resource."

    if not model.has_state("alpha"):
        return "has_state must acknowledge populated entries."

    if model.has_state("delta"):
        return "has_state should reject unknown tokens."

    if not model.transitions.has("beta"):
        return "Transitions dictionary should include populated entries."

    return null

func _test_transition_block_filtering() -> Variant:
    var model := MarkovModelResource.new()
    var valid_block := [{"token": "omega", "weight": 2.0}]
    model.transitions = {
        "valid": valid_block,
        "dictionary_only": {"token": "ignored"},
        "string_value": "invalid",
    }

    var retrieved := model.get_transition_block("valid")
    if not (retrieved is Array):
        return "get_transition_block must return an Array for valid entries."

    if retrieved != valid_block:
        return "get_transition_block should expose the stored transition array."

    var ignored_dictionary := model.get_transition_block("dictionary_only")
    if not (ignored_dictionary is Array) or not ignored_dictionary.is_empty():
        return "Non-array transition entries should be ignored."

    var ignored_missing := model.get_transition_block("missing")
    if not (ignored_missing is Array) or not ignored_missing.is_empty():
        return "Missing transition entries should return an empty array."

    var ignored_string := model.get_transition_block("string_value")
    if not (ignored_string is Array) or not ignored_string.is_empty():
        return "String transition entries should be ignored."

    return null

func _test_token_temperature_defaults() -> Variant:
    var model := MarkovModelResource.new()

    if model.default_temperature != 1.0:
        return "Default temperature should initialize to 1.0."

    if not (model.token_temperatures is Dictionary):
        return "token_temperatures must default to a Dictionary."

    if not model.token_temperatures.is_empty():
        return "token_temperatures should default to an empty Dictionary."

    model.token_temperatures["alpha"] = 0.75
    if float(model.token_temperatures["alpha"]) != 0.75:
        return "token_temperatures entries should accept numeric overrides."

    return null
