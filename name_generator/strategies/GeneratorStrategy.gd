
## Abstract base class for name generation strategies.
##
## Strategies consume a configuration dictionary and emit generated values.
## They also expose a consistent error-reporting interface so the calling code
## can surface actionable feedback to designers or telemetry systems.
extends Resource
class_name GeneratorStrategy

## Emitted whenever the strategy cannot produce a result due to configuration or
## data issues.  ``code`` identifies the error while ``message`` contains a
## user-facing explanation.  ``details`` can include extra structured context.
signal generation_error(code: String, message: String, details: Dictionary)

## Strategies override this method to produce output.  The default
## implementation simply returns an empty string so subclasses are not forced to
## call ``super``.
func generate(config: Dictionary) -> String:
    return ""

## Helper for subclasses that need to emit configurable errors.  The
## configuration dictionary can provide a nested ``errors`` dictionary where
## keys correspond to the error ``code`` value.  When the key is absent the
## ``default_message`` parameter is used instead.
func emit_configured_error(config: Dictionary, code: String, default_message: String, details: Dictionary = {}) -> void:
    var message := default_message
    if config.has("errors"):
        var overrides := config.get("errors")
        if typeof(overrides) == TYPE_DICTIONARY:
            message = overrides.get(code, default_message)

    emit_signal("generation_error", code, message, details)

extends RefCounted
class_name GeneratorStrategy

## Base class for all runtime name generation strategies.
##
## Strategies receive a configuration [Dictionary] along with a shared
## [RandomNumberGenerator] when [method generate] is invoked. Subclasses are
## expected to validate the configuration before use. To make this
## predictable for integrators, each strategy should override
## [method _get_expected_config_keys] and list the configuration keys they
## consume.
##
## The expected structure returned by [method _get_expected_config_keys]:
## ```gdscript
## return {
##     "required": PackedStringArray(["culture", "min_length"]),
##     "optional": {
##         "max_length": TYPE_INT,
##         "syllable_bias": TYPE_FLOAT,
##     }
## }
## ```
## * `required` — keys that must appear in the config dictionary. They may be
##   provided as either an [Array] of [String] values or a [PackedStringArray].
## * `optional` — a [Dictionary] that maps key names to expected Godot variant
##   types (as returned by [method typeof]).
##
## When the configuration does not satisfy the declared contract, helper
## methods in this class produce instances of [GeneratorError] that describe
## the problem. Strategies may forward these errors to calling code to deliver
## consistent diagnostics.
class GeneratorError:
    extends RefCounted

    ## Short machine readable code for the error (e.g. "missing_required_keys").
    var code: String

    ## Human readable summary of what went wrong.
    var message: String

    ## Additional contextual data that helps diagnose the issue.
    var details: Dictionary

    func _init(code: String, message: String, details: Dictionary = {}):
        self.code = code
        self.message = message
        self.details = details.duplicate(true)

    func to_dict() -> Dictionary:
        return {
            "code": code,
            "message": message,
            "details": details.duplicate(true),
        }

func generate(config: Dictionary, rng: RandomNumberGenerator) -> String:
    assert(false, "GeneratorStrategy.generate is abstract and must be overridden.")
    return ""

## Helper to create consistent error payloads.
func _make_error(code: String, message: String, details: Dictionary = {}) -> GeneratorError:
    return GeneratorError.new(code, message, details)

## Ensures that the provided config is a dictionary.
func _ensure_dictionary(config: Variant, context: String = "config") -> GeneratorError:
    if typeof(config) != TYPE_DICTIONARY:
        return _make_error(
            "invalid_config_type",
            "%s must be provided as a Dictionary." % context,
            {
                "received_type": typeof(config),
                "type_name": Variant.get_type_name(typeof(config)),
            },
        )
    return null

## Validates that every required key declared in [_get_expected_config_keys] exists.
func _validate_required_keys(config: Dictionary) -> GeneratorError:
    var expected := _get_expected_config_keys()
    if expected.is_empty() or not expected.has("required"):
        return null

    var required_keys = expected["required"]
    var normalized_required := PackedStringArray()
    if required_keys is PackedStringArray:
        normalized_required = required_keys
    else:
        for key in required_keys:
            normalized_required.append(String(key))

    var missing := PackedStringArray()
    for key in normalized_required:
        if not config.has(key):
            missing.append(key)

    if not missing.is_empty():
        return _make_error(
            "missing_required_keys",
            "Configuration is missing required keys: %s." % ", ".join(missing),
            {"missing": missing},
        )
    return null

## Validates optional key types declared in [_get_expected_config_keys].
func _validate_optional_key_types(config: Dictionary) -> GeneratorError:
    var expected := _get_expected_config_keys()
    if expected.is_empty() or not expected.has("optional"):
        return null

    var optional: Dictionary = expected["optional"]
    for key in optional.keys():
        if not config.has(key):
            continue

        var expected_type: int = optional[key]
        var value = config[key]
        if typeof(value) != expected_type:
            return _make_error(
                "invalid_key_type",
                "Configuration value for '%s' must be of type %s." % [key, Variant.get_type_name(expected_type)],
                {
                    "key": key,
                    "expected_type": expected_type,
                    "expected_type_name": Variant.get_type_name(expected_type),
                    "received_type": typeof(value),
                    "received_type_name": Variant.get_type_name(typeof(value)),
                },
            )
    return null

## Combined validation helper that strategies can call in their generate methods.
func _validate_config(config: Variant) -> GeneratorError:
    var error := _ensure_dictionary(config)
    if error:
        return error

    var dict_config: Dictionary = config

    error = _validate_required_keys(dict_config)
    if error:
        return error

    error = _validate_optional_key_types(dict_config)
    if error:
        return error

    return null

## Subclasses may override to advertise their configuration contract.
func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(),
        "optional": {},
    }

