extends RefCounted

const GeneratorStrategy := preload("res://name_generator/strategies/GeneratorStrategy.gd")
const SyllableChainStrategy := preload("res://name_generator/strategies/SyllableChainStrategy.gd")

const SYLLABLE_SET_PATH := "res://tests/test_assets/syllable_basic.tres"
const NO_MIDDLE_SET_PATH := "res://tests/test_assets/syllable_no_middle.tres"
const MISSING_SYLLABLE_SET_PATH := "res://tests/test_assets/missing_syllable_set.tres"

var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _checks.clear()

    _record("deterministic_sequences_across_configurations", func(): return _test_deterministic_generation())
    _record("error_invalid_syllable_set_path", func(): return _test_invalid_syllable_set_path())
    _record("error_missing_syllable_resource", func(): return _test_missing_syllable_resource())
    _record("error_missing_required_middles", func(): return _test_missing_required_middles())
    _record("error_unable_to_satisfy_min_length", func(): return _test_unable_to_satisfy_min_length())
    _record("post_processing_rules_transform_output", func(): return _test_post_processing_rules())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    return {
        "id": "syllable_chain_strategy",
        "name": "SyllableChainStrategy deterministic and error handling diagnostic",
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

func _base_config(overrides: Dictionary = {}) -> Dictionary:
    var config := {
        "syllable_set_path": SYLLABLE_SET_PATH,
    }
    for key in overrides.keys():
        config[key] = overrides[key]
    return config

func _test_deterministic_generation() -> Variant:
    var syllable_set := ResourceLoader.load(SYLLABLE_SET_PATH)
    if syllable_set == null:
        return "Failed to load test syllable set at %s" % SYLLABLE_SET_PATH

    var strategy := SyllableChainStrategy.new()

    var scenarios := [
        {
            "label": "no_required_middle_seed_2024",
            "seed": 2024,
            "config": _base_config({
                "require_middle": false,
                "middle_syllables": {"min": 0, "max": 1},
            }),
        },
        {
            "label": "require_middle_seed_17",
            "seed": 17,
            "config": _base_config({
                "require_middle": true,
                "middle_syllables": {"min": 1, "max": 3},
            }),
        },
        {
            "label": "min_length_growth_seed_404",
            "seed": 404,
            "config": _base_config({
                "require_middle": true,
                "middle_syllables": {"min": 1, "max": 4},
                "min_length": 9,
            }),
        },
    ]

    for scenario in scenarios:
        var config: Dictionary = scenario["config"].duplicate(true)
        var seed: int = scenario["seed"]

        var first_rng := RandomNumberGenerator.new()
        first_rng.seed = seed
        var second_rng := RandomNumberGenerator.new()
        second_rng.seed = seed

        var first_sequence: Array = []
        var second_sequence: Array = []
        for i in range(3):
            var first := strategy.generate(config, first_rng)
            if first is GeneratorStrategy.GeneratorError:
                return "Scenario %s returned unexpected error: %s" % [scenario["label"], first.code]
            first_sequence.append(first)

            if config.get("require_middle", false):
                var has_middle := false
                for middle in syllable_set.middles:
                    if String(first).find(String(middle)) != -1:
                        has_middle = true
                        break
                if not has_middle:
                    return "Scenario %s should include a middle syllable but generated '%s'" % [scenario["label"], first]

            var min_length := int(config.get("min_length", 0))
            if min_length > 0 and String(first).length() < min_length:
                return "Scenario %s expected min length %d but generated '%s'" % [scenario["label"], min_length, first]

            var second := strategy.generate(config, second_rng)
            if second is GeneratorStrategy.GeneratorError:
                return "Scenario %s second run errored with %s" % [scenario["label"], second.code]
            second_sequence.append(second)

        if first_sequence != second_sequence:
            return "Scenario %s produced different sequences for identical seeds." % scenario["label"]

        var alternate_rng := RandomNumberGenerator.new()
        alternate_rng.seed = seed + 991
        var alternate_sequence: Array = []
        for i in range(3):
            var generated := strategy.generate(config, alternate_rng)
            if generated is GeneratorStrategy.GeneratorError:
                return "Scenario %s alternate seed errored with %s" % [scenario["label"], generated.code]
            alternate_sequence.append(generated)

        if alternate_sequence == first_sequence:
            return "Scenario %s should yield a distinct sequence for a different seed." % scenario["label"]

    return null

func _test_invalid_syllable_set_path() -> Variant:
    var strategy := SyllableChainStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 10

    var result := strategy.generate({"syllable_set_path": ""}, rng)
    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected invalid path error but generation succeeded."

    if result.code != "invalid_syllable_set_path":
        return "Expected invalid_syllable_set_path code, received %s" % result.code

    return null

func _test_missing_syllable_resource() -> Variant:
    var strategy := SyllableChainStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 101

    var config := {"syllable_set_path": MISSING_SYLLABLE_SET_PATH}
    var result := strategy.generate(config, rng)
    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected missing resource error but generation succeeded."

    var error := result as GeneratorStrategy.GeneratorError
    if error.code != "missing_resource":
        return "Missing syllable set should return missing_resource, received %s" % error.code

    if not String(error.message).begins_with("Missing resource"):
        return "Missing syllable resource error should use the standard prefix."

    if String(error.details.get("path", "")) != MISSING_SYLLABLE_SET_PATH:
        return "Missing syllable resource error should include the failing path."

    return null

func _test_missing_required_middles() -> Variant:
    var strategy := SyllableChainStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 77

    var config := {
        "syllable_set_path": NO_MIDDLE_SET_PATH,
        "require_middle": true,
    }

    var result := strategy.generate(config, rng)
    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected missing_required_middles error but generation succeeded."

    if result.code != "missing_required_middles":
        return "Expected missing_required_middles code, received %s" % result.code

    return null

func _test_unable_to_satisfy_min_length() -> Variant:
    var strategy := SyllableChainStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 512

    var config := _base_config({
        "require_middle": false,
        "middle_syllables": {"min": 0, "max": 1},
        "min_length": 20,
    })

    var result := strategy.generate(config, rng)
    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected unable_to_satisfy_min_length error but generation succeeded."

    if result.code != "unable_to_satisfy_min_length":
        return "Expected unable_to_satisfy_min_length code, received %s" % result.code

    return null

func _test_post_processing_rules() -> Variant:
    var strategy := SyllableChainStrategy.new()
    var base_config := _base_config({
        "require_middle": true,
        "middle_syllables": {"min": 1, "max": 2},
    })

    var base_rng := RandomNumberGenerator.new()
    base_rng.seed = 909
    var base_result := strategy.generate(base_config, base_rng)
    if base_result is GeneratorStrategy.GeneratorError:
        return "Base generation failed with error %s" % base_result.code

    if String(base_result).length() < 2:
        return "Base result too short to verify post-processing: %s" % base_result

    var processed_config := base_config.duplicate(true)
    processed_config["post_processing_rules"] = [
        {"pattern": "^.", "replacement": "X"},
        {"pattern": ".$", "replacement": "Z"},
    ]

    var processed_rng := RandomNumberGenerator.new()
    processed_rng.seed = 909
    var processed_result := strategy.generate(processed_config, processed_rng)
    if processed_result is GeneratorStrategy.GeneratorError:
        return "Post-processing generation failed with error %s" % processed_result.code

    if processed_result == base_result:
        return "Post-processing rules did not alter the generated value."

    if not String(processed_result).begins_with("X"):
        return "Expected processed result to start with X but received %s" % processed_result

    if not String(processed_result).ends_with("Z"):
        return "Expected processed result to end with Z but received %s" % processed_result

    var base_inner := String(base_result).substr(1, String(base_result).length() - 2)
    var processed_inner := String(processed_result).substr(1, String(processed_result).length() - 2)
    if base_inner != processed_inner:
        return "Post-processing should only replace boundaries. Base: %s, Processed: %s" % [base_result, processed_result]

    return null
