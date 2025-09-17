extends GeneratorStrategy
class_name HybridStrategy

const NameGenerator := preload("res://name_generator/NameGenerator.gd")
const RNGStreamRouter := preload("res://name_generator/utils/RNGManager.gd")

const PLACEHOLDER_PATTERN := "\\$([A-Za-z0-9_]+)"

var _placeholder_regex: RegEx

func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(["steps"]),
        "optional": {
            "template": TYPE_STRING,
            "seed": TYPE_STRING,
        },
    }

func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    var validation_error := _validate_config(config)
    if validation_error:
        return validation_error

    var steps_variant := config.get("steps")
    if not (steps_variant is Array):
        return _make_error(
            "invalid_steps_type",
            "HybridStrategy expects 'steps' to be an Array of configuration dictionaries.",
            {
                "received_type": typeof(steps_variant),
                "type_name": Variant.get_type_name(typeof(steps_variant)),
            },
        )

    var steps: Array = steps_variant
    if steps.is_empty():
        return _make_error(
            "empty_steps",
            "HybridStrategy requires at least one step configuration.",
        )

    var rng_router := RNGStreamRouter.new(rng)
    var results: Array[String] = []
    var placeholders := {}
    var parent_seed := String(config.get("seed", ""))

    for index in range(steps.size()):
        var entry_variant := steps[index]
        if typeof(entry_variant) != TYPE_DICTIONARY:
            return _make_error(
                "invalid_step_entry",
                "HybridStrategy steps must contain Dictionary entries.",
                {
                    "index": index,
                    "entry_type": typeof(entry_variant),
                },
            )

        var entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
        var alias := String(entry.get("store_as", String(index))).strip_edges()
        entry.erase("store_as")

        var step_config := _extract_step_config(entry)
        if step_config is GeneratorError:
            return step_config

        step_config = _substitute_variant(step_config, placeholders)

        if not step_config.has("seed"):
            step_config["seed"] = "%s::step_%s" % [parent_seed, alias]

        var child_rng := rng_router.derive_rng([alias, String(index)])
        var result := NameGenerator.generate(step_config, child_rng)
        if result is Dictionary and result.has("code"):
            return _make_error(
                String(result.get("code", "hybrid_step_error")),
                "Hybrid step %s failed to generate." % alias,
                {
                    "index": index,
                    "alias": alias,
                    "details": result.get("details", {}),
                    "message": result.get("message", ""),
                },
            )

        var result_string := String(result)
        results.append(result_string)
        placeholders[String(index)] = result_string
        if not alias.is_empty():
            placeholders[alias] = result_string
    
    if config.has("template"):
        var template_string := String(config["template"])
        return _replace_placeholders(template_string, placeholders)

    return results.back()

func _extract_step_config(entry: Dictionary) -> Variant:
    if entry.has("config"):
        var payload := entry["config"]
        if typeof(payload) != TYPE_DICTIONARY:
            return _make_error(
                "invalid_step_config",
                "Hybrid step 'config' must be a Dictionary.",
                {
                    "received_type": typeof(payload),
                    "type_name": Variant.get_type_name(typeof(payload)),
                },
            )
        return (payload as Dictionary).duplicate(true)

    if not entry.has("strategy"):
        return _make_error(
            "missing_step_strategy",
            "Each hybrid step must define a 'strategy'.",
        )

    return entry.duplicate(true)

func _substitute_variant(value: Variant, placeholders: Dictionary) -> Variant:
    match typeof(value):
        TYPE_STRING:
            return _replace_placeholders(String(value), placeholders)
        TYPE_DICTIONARY:
            var clone := {}
            var dictionary: Dictionary = value
            for key in dictionary.keys():
                clone[key] = _substitute_variant(dictionary[key], placeholders)
            return clone
        TYPE_ARRAY:
            var array_value: Array = value
            var clone_array := []
            for element in array_value:
                clone_array.append(_substitute_variant(element, placeholders))
            return clone_array
        TYPE_PACKED_STRING_ARRAY:
            var packed: PackedStringArray = value
            var new_array := PackedStringArray()
            for element in packed:
                new_array.append(_replace_placeholders(element, placeholders))
            return new_array
        _:
            return value

func _replace_placeholders(text: String, placeholders: Dictionary) -> String:
    var regex := _get_placeholder_regex()
    var matches := regex.search_all(text)
    if matches.is_empty():
        return text

    var result := ""
    var cursor := 0
    for match in matches:
        var start_index := match.get_start()
        var end_index := match.get_end()
        result += text.substr(cursor, start_index - cursor)

        var key := match.get_string(1)
        if placeholders.has(key):
            result += String(placeholders[key])
        else:
            result += text.substr(start_index, end_index - start_index)

        cursor = end_index

    result += text.substr(cursor)
    return result

func _get_placeholder_regex() -> RegEx:
    if _placeholder_regex == null:
        _placeholder_regex = RegEx.new()
        var error := _placeholder_regex.compile(PLACEHOLDER_PATTERN)
        if error != OK:
            push_error("Failed to compile hybrid placeholder regex: %s" % PLACEHOLDER_PATTERN)
    return _placeholder_regex
