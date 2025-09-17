extends GeneratorStrategy
class_name TemplateStrategy

const RNGStreamRouter := preload("res://name_generator/utils/RNGManager.gd")
const NAME_GENERATOR_PATH := "res://name_generator/NameGenerator.gd"

const TOKEN_PATTERN := "\\[(?<token>[^\\[\\]]+)\\]"
const INTERNAL_DEPTH_KEY := "__template_depth"
const INTERNAL_MAX_DEPTH_KEY := "__template_max_depth"
const DEFAULT_MAX_DEPTH := 8

var _token_regex: RegEx
var _cached_name_generator_script: GDScript = null

func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(["template_string"]),
        "optional": {
            "sub_generators": TYPE_DICTIONARY,
            "max_depth": TYPE_INT,
            "seed": TYPE_STRING,
        },
    }

func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    var validation_error := _validate_config(config)
    if validation_error:
        return validation_error

    var template_value := config.get("template_string", "")
    if typeof(template_value) != TYPE_STRING:
        return _make_error(
            "invalid_template_type",
            "TemplateStrategy requires 'template_string' to be a String.",
            {
                "received_type": typeof(template_value),
                "type_name": type_string(typeof(template_value)),
            },
        )

    var template_string := String(template_value)
    var sub_generators: Dictionary = {}
    if config.has("sub_generators"):
        if typeof(config["sub_generators"]) != TYPE_DICTIONARY:
            return _make_error(
                "invalid_sub_generators_type",
                "TemplateStrategy optional 'sub_generators' must be a Dictionary.",
                {
                    "received_type": typeof(config["sub_generators"]),
                    "type_name": type_string(typeof(config["sub_generators"])),
                },
            )
        sub_generators = (config["sub_generators"] as Dictionary).duplicate(true)

    var max_depth := _resolve_max_depth(config)
    if max_depth <= 0:
        return _make_error(
            "invalid_max_depth",
            "Configuration value for 'max_depth' must be greater than zero.",
            {"max_depth": max_depth},
        )

    var current_depth := int(config.get(INTERNAL_DEPTH_KEY, 0))
    if current_depth >= max_depth:
        return _make_error(
            "template_recursion_depth_exceeded",
            "Template expansion exceeded the allowed recursion depth.",
            {
                "max_depth": max_depth,
                "current_depth": current_depth,
            },
        )

    var regex := _get_token_regex()
    var matches := regex.search_all(template_string)
    if matches.is_empty():
        return template_string

    var rng_router := RNGStreamRouter.new(rng)
    var token_counts := {}
    var cursor := 0
    var expanded := ""
    var parent_seed := String(config.get("seed", ""))

    for match in matches:
        var start_index := match.get_start()
        var end_index := match.get_end()
        expanded += template_string.substr(cursor, start_index - cursor)

        var token := _extract_token(match)
        token = token.strip_edges()
        if token.is_empty():
            return _make_error(
                "empty_token",
                "Template token at index %d must specify a sub-generator key." % start_index,
                {"start_index": start_index},
            )

        var occurrence := int(token_counts.get(token, 0))
        token_counts[token] = occurrence + 1

        var replacement := _resolve_token(
            token,
            occurrence,
            sub_generators,
            rng_router,
            parent_seed,
            current_depth,
            max_depth,
        )
        if replacement is GeneratorError:
            return replacement

        expanded += String(replacement)
        cursor = end_index

    expanded += template_string.substr(cursor)

    return expanded

func _resolve_max_depth(config: Dictionary) -> int:
    if config.has("max_depth"):
        return int(config["max_depth"])
    if config.has(INTERNAL_MAX_DEPTH_KEY):
        return int(config[INTERNAL_MAX_DEPTH_KEY])
    return DEFAULT_MAX_DEPTH

func _extract_token(match: RegExMatch) -> String:
    if match.names.has("token"):
        return match.get_string("token")
    return match.get_string(1)

func _resolve_token(
    token: String,
    occurrence: int,
    sub_generators: Dictionary,
    rng_router: RNGStreamRouter,
    parent_seed: String,
    current_depth: int,
    max_depth: int
) -> Variant:
    if not sub_generators.has(token):
        var available := PackedStringArray()
        for key in sub_generators.keys():
            available.append(String(key))
        return _make_error(
            "missing_template_token",
            "Template token '%s' does not have a configured sub-generator." % token,
            {
                "token": token,
                "available_tokens": available,
            },
        )

    var generator_config_variant := sub_generators[token]
    var type_error := _ensure_dictionary(generator_config_variant, "sub_generators['%s']" % token)
    if type_error:
        return type_error

    var generator_config: Dictionary = (generator_config_variant as Dictionary).duplicate(true)
    generator_config[INTERNAL_DEPTH_KEY] = current_depth + 1
    if not generator_config.has("max_depth") and not generator_config.has(INTERNAL_MAX_DEPTH_KEY):
        generator_config[INTERNAL_MAX_DEPTH_KEY] = max_depth

    if not generator_config.has("seed"):
        generator_config["seed"] = "%s::%s::%d" % [parent_seed, token, occurrence]

    var child_rng := rng_router.derive_rng([token, String(occurrence), String(current_depth + 1)])
    var result := _generate_via_processor(generator_config, child_rng)
    if result is Dictionary and result.has("code"):
        return _make_error(
            String(result.get("code", "template_child_error")),
            String(result.get("message", "Template sub-generator failed.")),
            result.get("details", {}),
        )

    return result

func _get_token_regex() -> RegEx:
    if _token_regex == null:
        _token_regex = RegEx.new()
        var error := _token_regex.compile(TOKEN_PATTERN)
        if error != OK:
            push_error("Failed to compile template token pattern: %s" % TOKEN_PATTERN)
    return _token_regex

func _generate_via_processor(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    if Engine.has_singleton("RNGProcessor"):
        var processor := Engine.get_singleton("RNGProcessor")
        if processor != null and processor.has_method("generate"):
            return processor.call("generate", config, rng)
    var generator := _resolve_name_generator_singleton()
    if generator != null:
        return generator.call("generate", config, rng)

    var script := _load_name_generator_script()
    if script != null:
        var fallback := script.new()
        if fallback != null:
            if fallback.has_method("_register_builtin_strategies"):
                fallback.call("_register_builtin_strategies")
            var result := fallback.call("generate", config, rng)
            if fallback is Node:
                fallback.free()
            return result

    return _make_error(
        "name_generator_unavailable",
        "TemplateStrategy requires the NameGenerator singleton or script to be available.",
        {
            "name_generator_path": NAME_GENERATOR_PATH,
        },
    )

func _resolve_name_generator_singleton() -> Object:
    ## Attempt to fetch the NameGenerator autoload safely without forcing a
    ## preload on the script. This avoids circular dependency issues while still
    ## allowing template expansion in games that rely on the singleton.
    if Engine.has_singleton("NameGenerator"):
        var singleton := Engine.get_singleton("NameGenerator")
        if singleton != null and singleton.has_method("generate"):
            return singleton
    return null

func _load_name_generator_script() -> GDScript:
    ## Lazily load and cache the NameGenerator script when the singleton is not
    ## registered. Diagnostic errors include the path so engineers can diagnose
    ## project configuration issues quickly.
    if _cached_name_generator_script == null:
        var script := load(NAME_GENERATOR_PATH)
        if script is GDScript:
            _cached_name_generator_script = script
    return _cached_name_generator_script

func describe() -> Dictionary:
    var notes := PackedStringArray([
        "template_string tokens like [name] trigger nested generator calls.",
        "sub_generators maps template tokens to configuration dictionaries.",
        "Provide max_depth to guard against accidental infinite recursion.",
        "Seed values cascade to child generators when omitted from sub-configs.",
    ])
    return {
        "expected_config": get_config_schema(),
        "notes": notes,
    }
