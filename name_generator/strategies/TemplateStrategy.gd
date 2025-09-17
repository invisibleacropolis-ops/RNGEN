extends GeneratorStrategy
class_name TemplateStrategy


## TemplateStrategy stitches together nested generator outputs based on a
## configurable template string.
##
## Tokens wrapped in square brackets (e.g. ``[title]``) are replaced by invoking
## child generator configurations declared in ``config.sub_generators``. Each
## token receives its own deterministic ``RandomNumberGenerator`` derived from
## the parent stream through ``RNGManager`` so repeated evaluations remain
## reproducible across runs.
const TOKEN_PATTERN := "\\[(?<token>[^\\[\\]]+)\\]"
const DEFAULT_MAX_DEPTH := 8
const INTERNAL_DEPTH_KEY := "__template_depth"
const INTERNAL_MAX_DEPTH_KEY := "__template_max_depth"

static var _token_regex: RegEx

func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    var validation_error := _validate_config(config)
    if validation_error:
        return validation_error

    if typeof(config["template_string"]) != TYPE_STRING:
        return _make_error(
            "invalid_key_type",
            "Configuration value for 'template_string' must be of type String.",
            {
                "key": "template_string",
                "expected_type": TYPE_STRING,
                "expected_type_name": Variant.get_type_name(TYPE_STRING),
                "received_type": typeof(config["template_string"]),
                "received_type_name": Variant.get_type_name(typeof(config["template_string"])),
            },
        )

    var template_string := String(config["template_string"])
    var sub_generators: Dictionary = {}
    if config.has("sub_generators"):
        sub_generators = config["sub_generators"]

    var current_depth := int(config.get(INTERNAL_DEPTH_KEY, 0))
    var max_depth := _resolve_max_depth(config)
    if max_depth <= 0:
        return _make_error(
            "invalid_max_depth",
            "Configuration value for 'max_depth' must be greater than zero.",
            {"max_depth": max_depth},
        )

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

    var rng_manager := RNGManager.new(rng)
    var token_counts := {}
    var cursor := 0
    var expanded := ""

    for match in matches:
        var start_index := match.get_start()
        var end_index := match.get_end()
        expanded += template_string.substr(cursor, start_index - cursor)

        var token := _extract_token(match)
        token = token.strip_edges()
        var occurrence := 0
        if token_counts.has(token):
            occurrence = int(token_counts[token])
        token_counts[token] = occurrence + 1

        var replacement := _resolve_token(
            token,
            occurrence,
            sub_generators,
            rng_manager,
            current_depth,
            max_depth,
        )
        if replacement is GeneratorError:
            return replacement

        expanded += String(replacement)
        cursor = end_index

    expanded += template_string.substr(cursor)

    return expanded


func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(["template_string"]),
        "optional": {
            "sub_generators": TYPE_DICTIONARY,
            "max_depth": TYPE_INT,
        },
    }


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
    rng_manager: RNGManager,
    current_depth: int,
    max_depth: int,
) -> Variant:
    if current_depth + 1 > max_depth:
        return _make_error(
            "template_recursion_depth_exceeded",
            "Template expansion exceeded the allowed recursion depth while resolving '%s'." % token,
            {
                "token": token,
                "max_depth": max_depth,
                "current_depth": current_depth,
            },
        )

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

    var path := [token, String(occurrence), String(current_depth + 1)]
    var child_rng := rng_manager.derive_rng(path)

    var result := _invoke_name_generator(generator_config, child_rng)
    if result is GeneratorError:
        return result

    return String(result)


func _invoke_name_generator(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    var callable := _resolve_name_generator_callable()
    if callable.is_null():
        return _make_error(
            "missing_name_generator",
            "NameGenerator.generate callable could not be resolved.",
            {
                "config": config,
            },
        )

    return callable.call(config, rng)


func _resolve_name_generator_callable() -> Callable:
    if Engine.has_singleton("NameGenerator"):
        var singleton := Engine.get_singleton("NameGenerator")
        if singleton != null and singleton.has_method("generate"):
            return Callable(singleton, "generate")

    if ResourceLoader.exists("res://name_generator/NameGenerator.gd"):
        var script := load("res://name_generator/NameGenerator.gd")
        if script != null:
            if script.has_method("generate"):
                return Callable(script, "generate")
            if script.can_instantiate():
                var instance := script.instantiate()
                if instance != null and instance.has_method("generate"):
                    return Callable(instance, "generate")

    return Callable()


static func _get_token_regex() -> RegEx:
    if _token_regex == null:
        _token_regex = RegEx.new()
        var error := _token_regex.compile(TOKEN_PATTERN)
        if error != OK:
            push_error("Failed to compile template token pattern: %s" % TOKEN_PATTERN)
    return _token_regex

const NameGenerator = preload("res://name_generator/NameGenerator.gd")
const RNGManager = preload("res://name_generator/utils/RNGManager.gd")

const INTERNAL_DEPTH_KEY := "__template_depth"
const INTERNAL_LINEAGE_KEY := "__template_lineage"
const DEFAULT_MAX_DEPTH := 10

## Default token pattern strips the surrounding brackets and any whitespace.
const _TOKEN_START := "["
const _TOKEN_END := "]"

func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(["template_string"]),
        "optional": {
            "sub_generators": TYPE_DICTIONARY,
            "max_depth": TYPE_INT,
        },
    }

func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    var error := _validate_config(config)
    if error:
        return error

    if rng == null:
        rng = RandomNumberGenerator.new()

    var template_string = config.get("template_string", "")
    if typeof(template_string) != TYPE_STRING:
        return _make_error(
            "invalid_template_type",
            "TemplateStrategy requires 'template_string' to be a String.",
            {
                "received_type": typeof(template_string),
                "type_name": Variant.get_type_name(typeof(template_string)),
            },
        )

    var sub_generators: Dictionary = {}
    if config.has("sub_generators"):
        var provided = config["sub_generators"]
        if typeof(provided) != TYPE_DICTIONARY:
            return _make_error(
                "invalid_sub_generators_type",
                "TemplateStrategy optional 'sub_generators' must be a Dictionary.",
                {
                    "received_type": typeof(provided),
                    "type_name": Variant.get_type_name(typeof(provided)),
                },
            )
        sub_generators = (provided as Dictionary).duplicate(true)

    var max_depth := DEFAULT_MAX_DEPTH
    if config.has("max_depth"):
        var provided_max_depth = config["max_depth"]
        if typeof(provided_max_depth) != TYPE_INT:
            return _make_error(
                "invalid_max_depth_type",
                "TemplateStrategy optional 'max_depth' must be an int.",
                {
                    "received_type": typeof(provided_max_depth),
                    "type_name": Variant.get_type_name(typeof(provided_max_depth)),
                },
            )
        max_depth = int(provided_max_depth)
        if max_depth <= 0:
            return _make_error(
                "invalid_max_depth_value",
                "TemplateStrategy 'max_depth' must be greater than zero.",
                {"max_depth": max_depth},
            )

    var current_depth := int(config.get(INTERNAL_DEPTH_KEY, 0))
    var lineage: Array = []
    if config.has(INTERNAL_LINEAGE_KEY):
        var provided_lineage = config[INTERNAL_LINEAGE_KEY]
        if provided_lineage is Array:
            lineage = (provided_lineage as Array).duplicate(true)

    if current_depth >= max_depth:
        return _make_error(
            "max_depth_exceeded",
            "TemplateStrategy exceeded the maximum recursion depth of %d." % max_depth,
            {
                "max_depth": max_depth,
                "lineage": lineage.duplicate(true),
            },
        )

    return _render_template(
        String(template_string),
        sub_generators,
        rng,
        current_depth,
        max_depth,
        lineage,
    )

func _render_template(
    template_string: String,
    sub_generators: Dictionary,
    rng: RandomNumberGenerator,
    current_depth: int,
    max_depth: int,
    lineage: Array,
) -> Variant:
    var token_rngs: Dictionary = {}
    var result := ""
    var index := 0

    while index < template_string.length():
        var next_token_start := template_string.find(_TOKEN_START, index)
        if next_token_start == -1:
            result += template_string.substr(index, template_string.length() - index)
            break

        result += template_string.substr(index, next_token_start - index)
        var token_close := template_string.find(_TOKEN_END, next_token_start + 1)
        if token_close == -1:
            return _make_error(
                "unclosed_token",
                "Template token starting at index %d is missing a closing ']'." % next_token_start,
                {"start_index": next_token_start},
            )

        var token_key := template_string.substr(next_token_start + 1, token_close - next_token_start - 1).strip_edges()
        if token_key.is_empty():
            return _make_error(
                "empty_token",
                "Template token at index %d must specify a sub-generator key." % next_token_start,
                {"start_index": next_token_start},
            )

        var token_value := _resolve_token(
            token_key,
            sub_generators,
            rng,
            token_rngs,
            current_depth,
            max_depth,
            lineage,
        )
        if token_value is GeneratorStrategy.GeneratorError:
            return token_value

        result += String(token_value)
        index = token_close + 1

    return result

func _resolve_token(
    token_key: String,
    sub_generators: Dictionary,
    parent_rng: RandomNumberGenerator,
    token_rngs: Dictionary,
    current_depth: int,
    max_depth: int,
    lineage: Array,
) -> Variant:
    if not sub_generators.has(token_key):
        return _make_error(
            "missing_sub_generator",
            "Template references unknown token '%s'." % token_key,
            {
                "token": token_key,
                "available_tokens": sub_generators.keys(),
            },
        )

    var token_config_variant = sub_generators[token_key]
    if typeof(token_config_variant) != TYPE_DICTIONARY:
        return _make_error(
            "invalid_sub_generator_config",
            "Configuration for token '%s' must be a Dictionary." % token_key,
            {
                "token": token_key,
                "received_type": typeof(token_config_variant),
                "type_name": Variant.get_type_name(typeof(token_config_variant)),
            },
        )

    var token_config: Dictionary = (token_config_variant as Dictionary).duplicate(true)
    token_config[INTERNAL_DEPTH_KEY] = current_depth + 1
    if not token_config.has("max_depth"):
        token_config["max_depth"] = max_depth
    var updated_lineage := lineage.duplicate(true)
    updated_lineage.append(token_key)
    token_config[INTERNAL_LINEAGE_KEY] = updated_lineage

    var token_rng: RandomNumberGenerator = token_rngs.get(token_key, null)
    if token_rng == null:
        token_rng = RNGManager.derive_child_rng(parent_rng, token_key, current_depth)
        token_rngs[token_key] = token_rng

    var generated_value := NameGenerator.generate(token_config, token_rng)
    if generated_value is GeneratorStrategy.GeneratorError:
        return generated_value

    if typeof(generated_value) != TYPE_STRING:
        return _make_error(
            "invalid_generated_type",
            "Generated value for token '%s' must be a String." % token_key,
            {
                "token": token_key,
                "received_type": typeof(generated_value),
                "type_name": Variant.get_type_name(typeof(generated_value)),
            },
        )

    return generated_value

