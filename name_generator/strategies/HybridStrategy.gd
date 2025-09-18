extends "res://name_generator/strategies/GeneratorStrategy.gd"
class_name HybridStrategy

const RNGStreamRouter := preload("res://name_generator/utils/RNGManager.gd")
const NAME_GENERATOR_PATH := "res://name_generator/NameGenerator.gd"

const PLACEHOLDER_PATTERN := "\\$([A-Za-z0-9_]+)"

var _placeholder_regex: RegEx
var _cached_name_generator_script: GDScript = null

func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(["steps"]),
        "optional": {
            "template": TYPE_STRING,
            "seed": TYPE_STRING,
        },
    }

func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    var validation_error: GeneratorError = _validate_config(config)
    if validation_error:
        return validation_error

    var steps_variant: Variant = config.get("steps")
    if not (steps_variant is Array):
        return _make_error(
            "invalid_steps_type",
            "HybridStrategy expects 'steps' to be an Array of configuration dictionaries.",
            {
                "received_type": typeof(steps_variant),
                "type_name": type_string(typeof(steps_variant)),
            },
        )

    var steps: Array = steps_variant
    if steps.is_empty():
        return _make_error(
            "empty_steps",
            "HybridStrategy requires at least one step configuration.",
        )

    var rng_router: RNGStreamRouter = RNGStreamRouter.new(rng)
    var results: Array[String] = []
    var placeholders: Dictionary = {}
    var parent_seed: String = String(config.get("seed", ""))

    for index in range(steps.size()):
        var entry_variant: Variant = steps[index]
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
        var alias: String = String(entry.get("store_as", str(index))).strip_edges()
        entry.erase("store_as")

        var step_config: Variant = _extract_step_config(entry)
        if step_config is GeneratorError:
            return step_config

        step_config = _substitute_variant(step_config, placeholders)

        if not step_config.has("seed"):
            step_config["seed"] = "%s::step_%s" % [parent_seed, alias]

        var child_rng: RandomNumberGenerator = rng_router.derive_rng([alias, str(index)])
        var result: Variant = _generate_via_processor(step_config, child_rng)
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

        var result_string: String = String(result)
        results.append(result_string)
        placeholders[str(index)] = result_string
        if not alias.is_empty():
            placeholders[alias] = result_string

    if config.has("template"):
        var template_string: String = String(config["template"])
        return _replace_placeholders(template_string, placeholders)

    return results.back()

func _extract_step_config(entry: Dictionary) -> Variant:
    if entry.has("config"):
        var payload: Variant = entry["config"]
        if typeof(payload) != TYPE_DICTIONARY:
            return _make_error(
                "invalid_step_config",
                "Hybrid step 'config' must be a Dictionary.",
                {
                    "received_type": typeof(payload),
                    "type_name": type_string(typeof(payload)),
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
            var clone: Dictionary = {}
            var dictionary: Dictionary = value
            for key in dictionary.keys():
                clone[key] = _substitute_variant(dictionary[key], placeholders)
            return clone
        TYPE_ARRAY:
            var array_value: Array = value
            var clone_array: Array = []
            for element in array_value:
                clone_array.append(_substitute_variant(element, placeholders))
            return clone_array
        TYPE_PACKED_STRING_ARRAY:
            var packed: PackedStringArray = value
            var new_array: PackedStringArray = PackedStringArray()
            for element in packed:
                new_array.append(_replace_placeholders(element, placeholders))
            return new_array
        _:
            return value

func _replace_placeholders(text: String, placeholders: Dictionary) -> String:
    var regex: RegEx = _get_placeholder_regex()
    var matches: Array = regex.search_all(text)
    if matches.is_empty():
        return text

    var result: String = ""
    var cursor: int = 0
    for match in matches:
        var start_index: int = match.get_start()
        var end_index: int = match.get_end()
        result += text.substr(cursor, start_index - cursor)

        var key: String = match.get_string(1)
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
        var error: int = _placeholder_regex.compile(PLACEHOLDER_PATTERN)
        if error != OK:
            push_error("Failed to compile hybrid placeholder regex: %s" % PLACEHOLDER_PATTERN)
    return _placeholder_regex

func _generate_via_processor(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    if Engine.has_singleton("RNGProcessor"):
        var processor: Object = Engine.get_singleton("RNGProcessor")
        if processor != null and processor.has_method("generate"):
            return processor.call("generate", config, rng)
    var generator: Object = _resolve_name_generator_singleton()
    if generator != null:
        return generator.call("generate", config, rng)

    var script: GDScript = _load_name_generator_script()
    if script != null:
        var fallback: Object = script.new()
        if fallback != null:
            if fallback.has_method("_register_builtin_strategies"):
                fallback.call("_register_builtin_strategies")
            var result: Variant = fallback.call("generate", config, rng)
            if fallback is Node:
                fallback.free()
            return result

    return _make_error(
        "name_generator_unavailable",
        "HybridStrategy requires the NameGenerator singleton or script to be available.",
        {
            "name_generator_path": NAME_GENERATOR_PATH,
        },
    )

func _resolve_name_generator_singleton() -> Object:
    ## Mirror TemplateStrategy's singleton resolution so hybrid expansions can
    ## safely delegate to the generator without triggering circular preloads.
    if Engine.has_singleton("NameGenerator"):
        var singleton: Object = Engine.get_singleton("NameGenerator")
        if singleton != null and singleton.has_method("generate"):
            return singleton
    return null

func _load_name_generator_script() -> GDScript:
    ## Lazily load the NameGenerator script as a last resort when the autoload is
    ## unavailable. The cached handle prevents redundant disk access if multiple
    ## hybrid steps fall back in succession during diagnostics.
    if _cached_name_generator_script == null:
        var script: Variant = load(NAME_GENERATOR_PATH)
        if script is GDScript:
            _cached_name_generator_script = script
    return _cached_name_generator_script

func describe() -> Dictionary:
    var notes := PackedStringArray([
        "steps executes sequential generator configurations and stitches results.",
        "Each step may supply store_as to expose its output to later placeholders.",
        "template can combine stored values using $placeholders.",
        "Seed defaults cascade from the top-level seed when omitted per step.",
    ])
    return {
        "expected_config": get_config_schema(),
        "notes": notes,
    }
