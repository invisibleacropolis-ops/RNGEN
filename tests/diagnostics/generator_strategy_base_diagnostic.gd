extends RefCounted

const GeneratorStrategy := preload("res://name_generator/strategies/GeneratorStrategy.gd")

class MockStrategy:
    extends GeneratorStrategy

    var _expected_config: Dictionary

    func _init(expected_config: Dictionary = {}):
        _expected_config = expected_config.duplicate(true)

    func _get_expected_config_keys() -> Dictionary:
        return _expected_config.duplicate(true)

    func generate(_config: Dictionary, _rng: RandomNumberGenerator) -> Variant:
        return ""

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("ensure_dictionary_rejects_non_dictionary", func(): _test_ensure_dictionary_rejects_non_dictionary())
    _run_test("validate_required_keys_reports_missing", func(): _test_validate_required_keys_reports_missing())
    _run_test("validate_optional_key_types_enforces_types", func(): _test_validate_optional_key_types_enforces_types())
    _run_test("validate_config_combines_all_checks", func(): _test_validate_config_combines_all_checks())
    _run_test("emit_configured_error_emits_signal", func(): _test_emit_configured_error_emits_signal())

    return {
        "suite": "generator_strategy_base",
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

func _test_ensure_dictionary_rejects_non_dictionary() -> Variant:
    var strategy := GeneratorStrategy.new()
    var error := strategy._ensure_dictionary(42, "configuration")
    if error == null:
        return "_ensure_dictionary should reject non-dictionary values."
    if error.code != "invalid_config_type":
        return "Expected invalid_config_type code but received %s." % error.code
    var expected_message := "configuration must be provided as a Dictionary."
    if error.message != expected_message:
        return "Expected message '%s' but received '%s'." % [expected_message, error.message]
    var details := error.details
    if not (details is Dictionary):
        return "Error details must be a dictionary."
    if details.get("received_type", -1) != TYPE_INT:
        return "Expected received_type TYPE_INT but received %s." % details.get("received_type")
    if details.get("type_name", "") != Variant.get_type_name(TYPE_INT):
        return "Expected type_name %s but received %s." % [Variant.get_type_name(TYPE_INT), details.get("type_name")]
    return null

func _test_validate_required_keys_reports_missing() -> Variant:
    var expectations := {
        "required": PackedStringArray(["required_key"]),
        "optional": {},
    }
    var strategy := MockStrategy.new(expectations)
    var error := strategy._validate_required_keys({})
    if error == null:
        return "_validate_required_keys should surface missing keys."
    if error.code != "missing_required_keys":
        return "Expected missing_required_keys code but received %s." % error.code
    var expected_message := "Configuration is missing required keys: required_key."
    if error.message != expected_message:
        return "Expected message '%s' but received '%s'." % [expected_message, error.message]
    var details := error.details
    if not (details is Dictionary):
        return "Missing key errors should expose detail dictionaries."
    var missing := details.get("missing", PackedStringArray())
    if missing.size() != 1 or missing[0] != "required_key":
        return "Missing key list should enumerate the absent key."
    return null

func _test_validate_optional_key_types_enforces_types() -> Variant:
    var expectations := {
        "required": PackedStringArray(),
        "optional": {"retries": TYPE_INT},
    }
    var strategy := MockStrategy.new(expectations)
    var error := strategy._validate_optional_key_types({"retries": "three"})
    if error == null:
        return "_validate_optional_key_types should reject mismatched types."
    if error.code != "invalid_key_type":
        return "Expected invalid_key_type code but received %s." % error.code
    var expected_message := "Configuration value for 'retries' must be of type %s." % Variant.get_type_name(TYPE_INT)
    if error.message != expected_message:
        return "Expected message '%s' but received '%s'." % [expected_message, error.message]
    var details := error.details
    if not (details is Dictionary):
        return "Type validation errors should expose detail dictionaries."
    if details.get("key", "") != "retries":
        return "Detail payload should echo the offending key."
    if details.get("expected_type", -1) != TYPE_INT:
        return "Detail payload should expose the expected Variant type."
    if details.get("expected_type_name", "") != Variant.get_type_name(TYPE_INT):
        return "Detail payload should expose the expected type name."
    if details.get("received_type", -1) != TYPE_STRING:
        return "Detail payload should expose the received Variant type."
    if details.get("received_type_name", "") != Variant.get_type_name(TYPE_STRING):
        return "Detail payload should expose the received type name."
    return null

func _test_validate_config_combines_all_checks() -> Variant:
    var expectations := {
        "required": PackedStringArray(["name"]),
        "optional": {"retries": TYPE_INT},
    }
    var strategy := MockStrategy.new(expectations)

    var valid_error := strategy._validate_config({
        "name": "alpha",
        "retries": 2,
    })
    if valid_error != null:
        return "Expected valid configuration to pass but received %s." % JSON.stringify(valid_error.to_dict())

    var type_error := strategy._validate_config(["not", "a", "dictionary"])
    if type_error == null or type_error.code != "invalid_config_type":
        return "_validate_config should forward type errors from _ensure_dictionary."

    var missing_error := strategy._validate_config({"retries": 1})
    if missing_error == null or missing_error.code != "missing_required_keys":
        return "_validate_config should enforce required keys."

    var optional_error := strategy._validate_config({"name": "beta", "retries": "two"})
    if optional_error == null or optional_error.code != "invalid_key_type":
        return "_validate_config should validate optional key types."

    return null

func _test_emit_configured_error_emits_signal() -> Variant:
    var strategy := GeneratorStrategy.new()
    var captured: Array[Dictionary] = []
    strategy.generation_error.connect(func(code: String, message: String, details: Dictionary):
        captured.append({
            "code": code,
            "message": message,
            "details": details.duplicate(true),
        })
    )

    var config := {
        "errors": {"custom_failure": "Override message"},
    }
    var expected_details := {"attempt": 5}
    var error := strategy.emit_configured_error(config, "custom_failure", "Default message", expected_details)
    if error == null:
        return "emit_configured_error should return a GeneratorError."
    if error.code != "custom_failure":
        return "Expected emitted error code to mirror the requested code."
    if error.message != "Override message":
        return "Expected override message to replace the default."
    if error.details != expected_details:
        return "Error detail payload should match the provided dictionary."

    expected_details["mutated"] = true
    if error.details.has("mutated"):
        return "GeneratorError instances should duplicate detail payloads."

    if captured.size() != 1:
        return "emit_configured_error should emit generation_error exactly once."

    var payload := captured[0]
    if payload.get("code", "") != error.code:
        return "Signal payload code should match the emitted error."
    if payload.get("message", "") != error.message:
        return "Signal payload message should match the emitted error."
    if payload.get("details", {}) != error.details:
        return "Signal payload details should match the emitted error."

    var fallback := strategy.emit_configured_error({}, "default_error", "Default text", {})
    if fallback.message != "Default text":
        return "Fallback message should use the default when no override exists."
    if captured.size() != 2:
        return "Second emit_configured_error call should trigger another signal."

    return null

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()
