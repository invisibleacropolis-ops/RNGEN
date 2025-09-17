extends RefCounted

const GeneratorStrategy := preload("res://name_generator/strategies/GeneratorStrategy.gd")
const MarkovChainStrategy := preload("res://name_generator/strategies/MarkovChainStrategy.gd")
const MarkovModelResource := preload("res://name_generator/resources/MarkovModelResource.gd")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

    _run_test("deterministic_seeded_walks", func(): return _test_deterministic_seeded_walks())
    _run_test("max_length_guard_rail", func(): return _test_max_length_guard())
    _run_test("validate_missing_start_tokens", func(): return _test_missing_start_tokens())
    _run_test("validate_invalid_transition_entries", func(): return _test_invalid_transition_entries())

    return {
        "suite": "MarkovChainStrategyDiagnostic",
        "id": "markov_chain_strategy",
        "total": _total,
        "passed": _passed,
        "failed": _failed,
        "failures": _failures.duplicate(true),
    }

func _run_test(name: String, callable: Callable) -> void:
    _total += 1
    var message := ""
    var success := true

    var result = callable.call()
    if result != null:
        success = false
        message = String(result)

    if success:
        _passed += 1
    else:
        _failed += 1
        _failures.append({
            "name": name,
            "message": message,
        })

func _test_deterministic_seeded_walks() -> Variant:
    var strategy := MarkovChainStrategy.new()
    var config := {
        "markov_model_path": "res://tests/test_assets/markov_basic.tres",
        "max_length": 8,
    }

    var first_rng := RandomNumberGenerator.new()
    first_rng.seed = 13371337
    var first := strategy.generate(config, first_rng)
    if first is GeneratorStrategy.GeneratorError:
        return "Seeded generation returned error: %s" % first.to_dict()

    var second_rng := RandomNumberGenerator.new()
    second_rng.seed = 13371337
    var second := strategy.generate(config, second_rng)
    if second is GeneratorStrategy.GeneratorError:
        return "Repeated seeded generation returned error: %s" % second.to_dict()

    if first != second:
        return "Seeded RNGs should produce deterministic walks. Received %s and %s." % [first, second]

    var observed := PackedStringArray()
    for seed in range(0, 128):
        var rng := RandomNumberGenerator.new()
        rng.seed = seed
        var value := strategy.generate(config, rng)
        if value is GeneratorStrategy.GeneratorError:
            return "Seed %s produced error: %s" % [seed, value.to_dict()]
        if not observed.has(String(value)):
            observed.append(String(value))
        if observed.size() >= 2:
            break

    if observed.is_empty():
        return "Expected to observe at least one deterministic output."

    if observed.size() < 2:
        return "Expected multiple deterministic walks but only observed: %s" % observed

    return null

func _test_max_length_guard() -> Variant:
    var strategy := MarkovChainStrategy.new()
    var config := {
        "markov_model_path": "res://tests/test_assets/markov_basic.tres",
        "max_length": 1,
    }

    var rng := RandomNumberGenerator.new()
    rng.seed = 42
    var result := strategy.generate(config, rng)

    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected max_length guard rail to return an error."

    var error: GeneratorStrategy.GeneratorError = result
    if error.code != "max_length_exceeded":
        return "Unexpected error code: %s" % error.to_dict()

    var details := error.details
    if details.get("max_length", 0) != 1:
        return "Error details should include the configured max_length."

    if String(details.get("partial_result", "")).is_empty():
        return "Partial result should include the truncated token walk."

    return null

func _test_missing_start_tokens() -> Variant:
    var strategy := MarkovChainStrategy.new()
    var model := _build_valid_model()
    model.start_tokens = []

    var error := strategy._validate_model(model)
    if error == null:
        return "Missing start tokens should be rejected by _validate_model."

    if error.code != "invalid_model_start_tokens":
        return "Unexpected error code for missing start tokens: %s" % error.to_dict()

    return null

func _test_invalid_transition_entries() -> Variant:
    var strategy := MarkovChainStrategy.new()
    var model := _build_valid_model()
    model.transitions = {
        "token_a": [{}],
    }

    var error := strategy._validate_model(model)
    if error == null:
        return "Missing transition token field should be rejected by _validate_model."

    if error.code != "missing_transition_token":
        return "Unexpected error code for invalid transitions: %s" % error.to_dict()

    return null

func _build_valid_model() -> MarkovModelResource:
    var model := MarkovModelResource.new()
    model.order = 1
    model.states = PackedStringArray(["token_a"])
    model.start_tokens = [{"token": "token_a", "weight": 1.0}]
    model.end_tokens = PackedStringArray(["<END>"])
    model.transitions = {
        "token_a": [{"token": "<END>", "weight": 1.0}],
    }
    model.default_temperature = 1.0
    model.token_temperatures = {}
    return model
