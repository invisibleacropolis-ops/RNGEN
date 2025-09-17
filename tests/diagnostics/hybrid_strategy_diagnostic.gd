extends RefCounted

const HybridStrategy := preload("res://name_generator/strategies/HybridStrategy.gd")
const GeneratorStrategy := preload("res://name_generator/strategies/GeneratorStrategy.gd")
const RNGStreamRouter := preload("res://name_generator/utils/RNGManager.gd")

const TOP_LEVEL_SEED := "diagnostic-hybrid-seed"

class MockNameGenerator:
    var calls: Array[Dictionary] = []

    func generate(config: Dictionary, rng: RandomNumberGenerator) -> String:
        var record := {
            "config": (config as Dictionary).duplicate(true),
            "seed": rng.seed,
            "state": rng.state,
        }
        var token := String(config.get("output_token", ""))
        var result := "%s::seed(%s)" % [token, rng.seed]
        record["result"] = result
        calls.append(record)
        return result

    func reset() -> void:
        calls.clear()

class MockProcessor:
    var calls: Array[Dictionary] = []
    var responses: Array = []
    var generator := MockNameGenerator.new()

    func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
        var record := {
            "config": (config as Dictionary).duplicate(true),
            "seed": rng.seed,
            "state": rng.state,
        }
        calls.append(record)

        var index := calls.size() - 1
        if index < responses.size():
            var response := responses[index]
            if response is Callable:
                return response.call(config, rng)
            return response

        return generator.generate(config, rng)

    func reset() -> void:
        calls.clear()
        generator.reset()

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("hybrid_sequences_are_deterministic", func(): return _test_hybrid_sequences())
    _run_test("invalid_steps_type", func(): return _test_invalid_steps_type())
    _run_test("invalid_step_entry", func(): return _test_invalid_step_entry())
    _run_test("missing_step_strategy", func(): return _test_missing_step_strategy())
    _run_test("child_strategy_failure_propagates", func(): return _test_child_strategy_failure())

    return {
        "id": "hybrid_strategy",
        "suite": "HybridStrategyDiagnostic",
        "total": _total,
        "passed": _passed,
        "failed": _failed,
        "failures": _failures.duplicate(true),
    }

func _run_test(name: String, callable: Callable) -> void:
    _total += 1
    var message := callable.call()
    if message == null:
        _passed += 1
        return

    _failed += 1
    _failures.append({
        "name": name,
        "message": String(message),
    })

func _test_hybrid_sequences() -> Variant:
    var strategy := HybridStrategy.new()
    var processor := MockProcessor.new()

    var parent_rng_a := RandomNumberGenerator.new()
    parent_rng_a.seed = 24681357

    var config_a := _build_hybrid_config()

    var router := RNGStreamRouter.new(parent_rng_a)
    var expected_seed_first := router.derive_rng(["phase_one", "0"]).seed
    var expected_seed_second := router.derive_rng(["phase_two", "1"]).seed
    var expected_seed_third := router.derive_rng(["2", "2"]).seed

    var result_a := _with_processor(processor, func():
        return strategy.generate(config_a, parent_rng_a)
    )

    if result_a is GeneratorStrategy.GeneratorError:
        return "HybridStrategy returned error: %s" % result_a.message

    if processor.calls.size() != 3:
        return "HybridStrategy should execute three configured steps."

    var generator_calls := processor.generator.calls
    if generator_calls.size() != 3:
        return "Mock generator should capture each hybrid step invocation."

    var first_call := processor.calls[0]
    var second_call := processor.calls[1]
    var third_call := processor.calls[2]

    if first_call.get("seed", 0) != expected_seed_first:
        return "Child RNG seed for phase_one should derive from parent seed."
    if second_call.get("seed", 0) != expected_seed_second:
        return "Child RNG seed for phase_two should derive from parent seed."
    if third_call.get("seed", 0) != expected_seed_third:
        return "Child RNG seed for index placeholder should derive from parent seed."

    if first_call.get("config", {}).get("seed", "") != "%s::step_phase_one" % TOP_LEVEL_SEED:
        return "Hybrid steps must inject derived seed for phase_one."
    if second_call.get("config", {}).get("seed", "") != "%s::step_phase_two" % TOP_LEVEL_SEED:
        return "Hybrid steps must inject derived seed for phase_two."
    if third_call.get("config", {}).get("seed", "") != "%s::step_2" % TOP_LEVEL_SEED:
        return "Hybrid steps must inject derived seed for positional alias."

    if String(generator_calls[1].get("config", {}).get("output_token", "")).find("$") != -1:
        return "Placeholders should be resolved before invoking downstream strategies."
    if String(generator_calls[2].get("config", {}).get("output_token", "")).find("$") != -1:
        return "Index placeholders should be resolved before the final step executes."

    var expected_output_a := "Report: %s | %s | %s" % [
        generator_calls[0].get("result", ""),
        generator_calls[1].get("result", ""),
        generator_calls[2].get("result", ""),
    ]
    if String(result_a) != expected_output_a:
        return "Hybrid template should stitch together step results deterministically."
    if String(result_a).find("$") != -1:
        return "Final template output must not contain unresolved placeholders."

    var parent_rng_b := RandomNumberGenerator.new()
    parent_rng_b.seed = 24681357
    var processor_b := MockProcessor.new()
    var config_b := _build_hybrid_config()

    var result_b := _with_processor(processor_b, func():
        return strategy.generate(config_b, parent_rng_b)
    )

    if String(result_b) != String(result_a):
        return "Hybrid strategy should produce the same output for identical seeds and configs."

    for index in range(processor.calls.size()):
        var first_seed := processor.calls[index].get("seed", -1)
        var second_seed := processor_b.calls[index].get("seed", -2)
        if first_seed != second_seed:
            return "Derived RNG seeds must be stable across identical runs."

    return null

func _test_invalid_steps_type() -> Variant:
    var strategy := HybridStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 123

    var result := strategy.generate({"steps": "not-an-array"}, rng)
    if not (result is GeneratorStrategy.GeneratorError):
        return "HybridStrategy should return an error when steps is not an array."
    if result.code != "invalid_steps_type":
        return "Expected invalid_steps_type error but received %s." % result.code

    var details := result.details
    if details.get("type_name", "") != "String":
        return "Error details should report the received steps type."

    return null

func _test_invalid_step_entry() -> Variant:
    var strategy := HybridStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 456

    var result := strategy.generate({"steps": ["invalid-entry"]}, rng)
    if not (result is GeneratorStrategy.GeneratorError):
        return "HybridStrategy should surface an error for non-dictionary step entries."
    if result.code != "invalid_step_entry":
        return "Expected invalid_step_entry error but received %s." % result.code

    var details := result.details
    if details.get("index", -1) != 0:
        return "Error details should include the failing step index."

    return null

func _test_missing_step_strategy() -> Variant:
    var strategy := HybridStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 789

    var result := strategy.generate({"steps": [{}]}, rng)
    if not (result is GeneratorStrategy.GeneratorError):
        return "HybridStrategy should return an error when a step omits its strategy."
    if result.code != "missing_step_strategy":
        return "Expected missing_step_strategy error but received %s." % result.code

    return null

func _test_child_strategy_failure() -> Variant:
    var strategy := HybridStrategy.new()
    var processor := MockProcessor.new()
    processor.responses.append({
        "code": "mock_failure",
        "message": "Simulated child strategy failure",
        "details": {"context": "diagnostic"},
    })

    var rng := RandomNumberGenerator.new()
    rng.seed = 42

    var config := {
        "steps": [
            {
                "strategy": "mock",
                "output_token": "alpha",
                "store_as": "phase_one",
            },
        ],
    }

    var result := _with_processor(processor, func():
        return strategy.generate(config, rng)
    )

    if not (result is GeneratorStrategy.GeneratorError):
        return "HybridStrategy should convert child strategy failures into GeneratorError instances."
    if result.code != "mock_failure":
        return "HybridStrategy should propagate the child error code."
    if result.message.find("phase_one") == -1:
        return "HybridStrategy error messages should mention the failing step alias."

    var details := result.details
    if details.get("message", "") != "Simulated child strategy failure":
        return "HybridStrategy should expose the child error message in the details payload."
    if details.get("details", {}).get("context", "") != "diagnostic":
        return "HybridStrategy should propagate child error details."

    return null

func _build_hybrid_config() -> Dictionary:
    return {
        "seed": TOP_LEVEL_SEED,
        "steps": [
            {
                "strategy": "mock",
                "output_token": "alpha",
                "store_as": "phase_one",
            },
            {
                "strategy": "mock",
                "output_token": "$phase_one-beta",
                "store_as": "phase_two",
            },
            {
                "strategy": "mock",
                "output_token": "$phase_two::gamma",
            },
        ],
        "template": "Report: $phase_one | $phase_two | $2",
    }

func _with_processor(processor: MockProcessor, callable: Callable) -> Variant:
    var original_has := Engine.has_singleton
    var original_get := Engine.get_singleton

    Engine.has_singleton = func(name: String) -> bool:
        if name == "RNGProcessor":
            return true
        return original_has.call(name)

    Engine.get_singleton = func(name: String) -> Variant:
        if name == "RNGProcessor":
            return processor
        return original_get.call(name)

    var outcome := callable.call()

    Engine.has_singleton = original_has
    Engine.get_singleton = original_get

    return outcome

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()
