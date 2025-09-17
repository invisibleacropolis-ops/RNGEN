extends RefCounted
class_name GeneratorStrategy

## Emitted when a strategy cannot generate a result.
signal generation_error(code: String, message: String, details: Dictionary)

## Lightweight error container returned by strategies when generation fails.
class GeneratorError:
    extends RefCounted

    var code: String
    var message: String
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

func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    push_error("GeneratorStrategy.generate must be implemented by subclasses.")
    return ""

func _make_error(code: String, message: String, details: Dictionary = {}) -> GeneratorError:
    return GeneratorError.new(code, message, details)

func _ensure_dictionary(value: Variant, context: String = "config") -> GeneratorError:
    if typeof(value) != TYPE_DICTIONARY:
        return _make_error(
            "invalid_config_type",
            "%s must be provided as a Dictionary." % context,
            {
                "received_type": typeof(value),
                "type_name": Variant.get_type_name(typeof(value)),
            },
        )
    return null

func _validate_config(config: Variant) -> GeneratorError:
    var type_error := _ensure_dictionary(config)
    if type_error:
        return type_error

    var dictionary: Dictionary = config

    var required_error := _validate_required_keys(dictionary)
    if required_error:
        return required_error

    var optional_error := _validate_optional_key_types(dictionary)
    if optional_error:
        return optional_error

    return null

func _validate_required_keys(config: Dictionary) -> GeneratorError:
    var expectations := _get_expected_config_keys()
    if expectations.is_empty() or not expectations.has("required"):
        return null

    var required_keys := expectations["required"]
    var normalized := PackedStringArray()
    if required_keys is PackedStringArray:
        normalized = required_keys
    else:
        for key in required_keys:
            normalized.append(String(key))

    var missing := PackedStringArray()
    for key in normalized:
        if not config.has(key):
            missing.append(key)

    if missing.is_empty():
        return null

    return _make_error(
        "missing_required_keys",
        "Configuration is missing required keys: %s." % ", ".join(missing),
        {"missing": missing},
    )

func _validate_optional_key_types(config: Dictionary) -> GeneratorError:
    var expectations := _get_expected_config_keys()
    if expectations.is_empty() or not expectations.has("optional"):
        return null

    var optional: Dictionary = expectations["optional"]
    for key in optional.keys():
        if not config.has(key):
            continue

        var expected_type: int = optional[key]
        var value := config[key]
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

func emit_configured_error(
    config: Dictionary,
    code: String,
    default_message: String,
    details: Dictionary = {}
) -> GeneratorError:
    var message := default_message
    if config.has("errors"):
        var overrides := config.get("errors")
        if typeof(overrides) == TYPE_DICTIONARY and overrides.has(code):
            message = String(overrides[code])

    var error := _make_error(code, message, details)
    emit_signal("generation_error", error.code, error.message, error.details)
    return error

func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(),
        "optional": {},
    }

func get_config_schema() -> Dictionary:
    ## Public wrapper around the protected `_get_expected_config_keys` hook.
    ##
    ## Strategies frequently need to surface their expected configuration to
    ## tooling or editor UIs. Exposing a public accessor keeps that data
    ## consistent without forcing subclasses to duplicate schema definitions.
    return _get_expected_config_keys()

func describe() -> Dictionary:
    ## Provide a structured description of the strategy. Concrete strategies can
    ## override this to append additional metadata or human-readable guidance.
    return {
        "expected_config": get_config_schema(),
        "notes": PackedStringArray(),
    }
