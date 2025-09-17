extends GeneratorStrategy
class_name TemplateStrategy

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
