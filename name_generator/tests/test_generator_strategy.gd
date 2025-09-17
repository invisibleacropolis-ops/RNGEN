extends RefCounted

const GeneratorStrategy := preload("res://name_generator/strategies/GeneratorStrategy.gd")
const ArrayUtils := preload("res://name_generator/utils/ArrayUtils.gd")

class MockStrategy:
    extends GeneratorStrategy

    func _get_expected_config_keys() -> Dictionary:
        return {
            "required": PackedStringArray(["values"]),
            "optional": {
                "uppercase": TYPE_BOOL,
                "prefix": TYPE_STRING,
            },
        }

    func generate(config: Dictionary, rng: RandomNumberGenerator) -> String:
        var error := _validate_config(config)
        if error:
            var payload := error.to_dict()
            push_error("MockStrategy received invalid config: %s" % payload)
            assert(false, error.message)

        var normalized: Array[String] = []
        for value in config["values"]:
            normalized.append(String(value))

        var selected: String = ArrayUtils.pick_random_deterministic(normalized, rng)

        if config.get("uppercase", false):
            selected = selected.to_upper()

        if config.has("prefix"):
            selected = "%s%s" % [String(config["prefix"]), selected]

        return selected

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

    _run_test("happy_path_generates_expected_format", func(): _test_happy_path())
    _run_test("validation_fails_when_config_not_dictionary", func(): _test_invalid_config_type())
    _run_test("validation_fails_when_required_key_missing", func(): _test_missing_required_key())
    _run_test("validation_fails_on_optional_type_mismatch", func(): _test_invalid_optional_type())
    _run_test("deterministic_rng_produces_reproducible_sequences", func(): _test_deterministic_rng())

    return {
        "suite": "GeneratorStrategy",
        "total": _total,
        "passed": _passed,
        "failed": _failed,
        "failures": _failures.duplicate(true),
    }

func _run_test(name: String, callable: Callable) -> void:
    _total += 1
    var error_message = ""
    var success := true

    var result = callable.call()
    if result != null:
        success = false
        error_message = String(result)

    if success:
        _passed += 1
    else:
        _failed += 1
        _failures.append({
            "name": name,
            "message": error_message,
        })

func _test_happy_path() -> Variant:
    var strategy := MockStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 1337

    var config := {
        "values": ["nova", "luna", "sol"],
        "uppercase": true,
        "prefix": "Star-",
    }

    var result := strategy.generate(config, rng)

    if not result.begins_with("Star-"):
        return "Generated value must include the configured prefix."

    var prefix_length := String(config["prefix"]).length()
    var core := result.substr(prefix_length, result.length() - prefix_length)

    if core != core.to_upper():
        return "Generated value must honor the uppercase flag."

    var allowed: Array[String] = []
    for value in config["values"]:
        allowed.append(String(value).to_upper())

    if not allowed.has(core):
        return "Generated value must come from the provided pool."

    return null

func _test_invalid_config_type() -> Variant:
    var strategy := MockStrategy.new()
    var error := strategy._validate_config("not a dictionary")

    if error == null:
        return "Validation should fail when the config is not a dictionary."

    if error.code != "invalid_config_type":
        return "Unexpected error code %s for invalid config type." % error.code

    return null

func _test_missing_required_key() -> Variant:
    var strategy := MockStrategy.new()
    var error := strategy._validate_config({})

    if error == null:
        return "Validation should fail when required keys are missing."

    if error.code != "missing_required_keys":
        return "Unexpected error code %s when required keys are missing." % error.code

    if not error.details.has("missing"):
        return "Error details should list the missing keys."

    var missing: PackedStringArray = error.details["missing"]
    if not missing.has("values"):
        return "Missing keys list should include 'values'."

    return null

func _test_invalid_optional_type() -> Variant:
    var strategy := MockStrategy.new()
    var config := {
        "values": ["atlas"],
        "uppercase": "yes please",
    }

    var error := strategy._validate_config(config)

    if error == null:
        return "Validation should fail when optional keys have the wrong type."

    if error.code != "invalid_key_type":
        return "Unexpected error code %s for invalid key types." % error.code

    if error.details.get("key", "") != "uppercase":
        return "Error details should identify the invalid key."

    if error.details.get("expected_type", -1) != TYPE_BOOL:
        return "Error details should describe the expected type for the invalid key."

    return null

func _test_deterministic_rng() -> Variant:
    var strategy := MockStrategy.new()
    var config := {
        "values": ["aurora", "selene", "lyra", "draco", "orion"],
    }

    var first_rng := RandomNumberGenerator.new()
    first_rng.seed = 42

    var second_rng := RandomNumberGenerator.new()
    second_rng.seed = 42

    var first_sequence: Array[String] = []
    var second_sequence: Array[String] = []

    for i in range(5):
        first_sequence.append(strategy.generate(config, first_rng))
        second_sequence.append(strategy.generate(config, second_rng))

    if first_sequence != second_sequence:
        return "Sequences generated with identical seeds must match."

    var alternate_rng := RandomNumberGenerator.new()
    alternate_rng.seed = 314159

    var alternate_sequence: Array[String] = []
    for i in range(5):
        alternate_sequence.append(strategy.generate(config, alternate_rng))

    if alternate_sequence == first_sequence:
        return "Different seeds should produce a different sequence of values."

    return null
