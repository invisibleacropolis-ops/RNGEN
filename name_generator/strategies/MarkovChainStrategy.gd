extends "res://name_generator/strategies/GeneratorStrategy.gd"
class_name MarkovChainStrategy

const MarkovModelResource := preload("res://name_generator/resources/MarkovModelResource.gd")

## MarkovChainStrategy composes tokens by walking through a weighted Markov
## model. It loads configuration from a [MarkovModelResource] and uses the
## provided random number generator to produce deterministic-yet-varied results.

var _state_rngs: Dictionary = {}

func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    var error: GeneratorError = _validate_config(config)
    if error:
        return error

    var markov_path_variant: Variant = config.get("markov_model_path")
    if typeof(markov_path_variant) != TYPE_STRING:
        return _make_error(
            "invalid_markov_model_path",
            "Configuration value 'markov_model_path' must be a String path to a MarkovModelResource.",
            {"received_type": typeof(markov_path_variant)},
        )

    var markov_path: String = markov_path_variant
    if markov_path.is_empty():
        return _make_error(
            "missing_markov_model_path",
            "Configuration key 'markov_model_path' cannot be empty.",
        )

    var max_length_variant: Variant = config.get("max_length", 32)
    if typeof(max_length_variant) != TYPE_INT:
        return _make_error(
            "invalid_max_length_type",
            "Configuration value 'max_length' must be an integer when provided.",
            {"received_type": typeof(max_length_variant)},
        )
    var max_length: int = int(max_length_variant)
    if max_length <= 0:
        return _make_error(
            "invalid_max_length_value",
            "Configuration value 'max_length' must be greater than zero.",
            {"received_value": max_length},
        )

    var model_result: Variant = _load_model(markov_path)
    if model_result is GeneratorStrategy.GeneratorError:
        return model_result
    var model: MarkovModelResource = model_result

    var validation_error: GeneratorError = _validate_model(model)
    if validation_error:
        return validation_error

    _state_rngs.clear()

    var tokens: Array[String] = []
    var step_count: int = 0
    var next_token_result: Variant = _sample_start_token(model, rng)
    if next_token_result is GeneratorStrategy.GeneratorError:
        return next_token_result
    var next_token: String = next_token_result

    while true:
        if not model.end_tokens.has(next_token):
            tokens.append(next_token)

        if model.end_tokens.has(next_token):
            break

        step_count += 1
        if step_count >= max_length:
            return _make_error(
                "max_length_exceeded",
                "Failed to reach a terminating token before exceeding max_length.",
                {
                    "max_length": max_length,
                    "partial_result": "".join(tokens),
                },
            )

        var sampled: Variant = _sample_transition(model, next_token, rng)
        if sampled is GeneratorStrategy.GeneratorError:
            return sampled
        next_token = sampled

    return "".join(tokens)

func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(["markov_model_path"]),
        "optional": {
            "max_length": TYPE_INT,
        },
    }

func _load_model(path: String) -> Variant:
    if not ResourceLoader.exists(path):
        return _make_error(
            "missing_resource",
            "Markov model resource could not be found at '%s'." % path,
            {"path": path},
        )

    var resource: Resource = ResourceLoader.load(path)
    if resource == null:
        return _make_error(
            "resource_load_failed",
            "Failed to load Markov model resource at '%s'." % path,
            {"path": path},
        )

    if resource is MarkovModelResource:
        return resource

    return _make_error(
        "invalid_resource_type",
        "Resource at '%s' must be a MarkovModelResource." % path,
        {
            "path": path,
            "received_type": resource.get_class(),
        },
    )

func _validate_model(model: MarkovModelResource) -> GeneratorError:
    if model.states.is_empty():
        return _make_error(
            "invalid_model_states",
            "Markov model must declare at least one token in 'states'.",
        )

    if model.start_tokens.is_empty():
        return _make_error(
            "invalid_model_start_tokens",
            "Markov model must define at least one start token.",
        )

    if model.end_tokens.is_empty():
        return _make_error(
            "invalid_model_end_tokens",
            "Markov model must define at least one terminating token.",
        )

    if typeof(model.transitions) != TYPE_DICTIONARY:
        return _make_error(
            "invalid_transitions_type",
            "Markov model transitions must be stored as a Dictionary mapping tokens to Arrays of Dictionaries.",
            {"received_type": typeof(model.transitions)},
        )

    if model.default_temperature <= 0.0:
        return _make_error(
            "invalid_default_temperature",
            "Markov model default_temperature must be greater than zero.",
            {"default_temperature": model.default_temperature},
        )

    for token_key in model.token_temperatures.keys():
        var temperature_value: Variant = model.token_temperatures[token_key]
        if typeof(temperature_value) != TYPE_FLOAT and typeof(temperature_value) != TYPE_INT:
            return _make_error(
                "invalid_token_temperature_type",
                "Token temperature overrides must be numeric values.",
                {
                    "token": token_key,
                    "received_type": typeof(temperature_value),
                },
            )
        if float(temperature_value) <= 0.0:
            return _make_error(
                "invalid_token_temperature_value",
                "Token temperature overrides must be greater than zero.",
                {
                    "token": token_key,
                    "received_value": temperature_value,
                },
            )

    var referenced_tokens := PackedStringArray()

    var start_validation: GeneratorError = _validate_transition_array(model.start_tokens, "start_tokens", referenced_tokens)
    if start_validation:
        return start_validation

    for key in model.transitions.keys():
        var array_variant: Variant = model.transitions[key]
        if typeof(array_variant) != TYPE_ARRAY:
            return _make_error(
                "invalid_transition_block",
                "Transitions for token '%s' must be provided as an Array of Dictionaries." % key,
                {
                    "token": key,
                    "received_type": typeof(array_variant),
                },
            )

        var transition_array: Array = array_variant
        var transition_error: GeneratorError = _validate_transition_array(transition_array, "transitions[%s]" % key, referenced_tokens)
        if transition_error:
            return transition_error

    for referenced_token in referenced_tokens:
        if not model.states.has(referenced_token) and not model.end_tokens.has(referenced_token):
            return _make_error(
                "unknown_token_reference",
                "Transition references unknown token '%s'." % referenced_token,
                {"token": referenced_token},
            )

    return null

func _validate_transition_array(array: Array, context: String, referenced_tokens: PackedStringArray) -> GeneratorError:
    if array.is_empty():
        return _make_error(
            "empty_transition_block",
            "%s must contain at least one entry." % context,
        )

    for item in array:
        if typeof(item) != TYPE_DICTIONARY:
            return _make_error(
                "invalid_transition_entry_type",
                "%s entries must be Dictionaries." % context,
                {"received_type": typeof(item)},
            )

        if not item.has("token"):
            return _make_error(
                "missing_transition_token",
                "%s entries must include a 'token' field." % context,
            )

        var token_value: Variant = item["token"]
        if typeof(token_value) != TYPE_STRING:
            return _make_error(
                "invalid_transition_token_type",
                "'token' values inside %s must be Strings." % context,
                {"received_type": typeof(token_value)},
            )

        if not referenced_tokens.has(token_value):
            referenced_tokens.append(token_value)

        var weight_value: Variant = item.get("weight", 1.0)
        if typeof(weight_value) != TYPE_FLOAT and typeof(weight_value) != TYPE_INT:
            return _make_error(
                "invalid_transition_weight_type",
                "'weight' in %s must be numeric when provided." % context,
                {"received_type": typeof(weight_value)},
            )
        if float(weight_value) <= 0.0:
            return _make_error(
                "invalid_transition_weight_value",
                "'weight' in %s must be greater than zero." % context,
                {"received_value": weight_value},
            )

        if item.has("temperature"):
            var temperature_value: Variant = item["temperature"]
            if typeof(temperature_value) != TYPE_FLOAT and typeof(temperature_value) != TYPE_INT:
                return _make_error(
                    "invalid_transition_temperature_type",
                    "'temperature' in %s must be numeric when provided." % context,
                    {"received_type": typeof(temperature_value)},
                )
            if float(temperature_value) <= 0.0:
                return _make_error(
                    "invalid_transition_temperature_value",
                    "'temperature' in %s must be greater than zero when provided." % context,
                    {"received_value": temperature_value},
                )

    return null

func _sample_start_token(model: MarkovModelResource, base_rng: RandomNumberGenerator) -> Variant:
    var selection: Variant = _sample_from_options(model, "__start__", model.start_tokens, base_rng)
    if selection is GeneratorStrategy.GeneratorError:
        return selection
    return selection["token"]

func _sample_transition(model: MarkovModelResource, from_token: String, base_rng: RandomNumberGenerator) -> Variant:
    if not model.transitions.has(from_token):
        return _make_error(
            "missing_transition_for_token",
            "Markov model does not define transitions for token '%s'." % from_token,
            {"token": from_token},
        )

    var options: Array = model.transitions[from_token]
    var selection: Variant = _sample_from_options(model, from_token, options, base_rng)
    if selection is GeneratorStrategy.GeneratorError:
        return selection
    return selection["token"]

func _sample_from_options(model: MarkovModelResource, state_id: String, options: Array, base_rng: RandomNumberGenerator) -> Variant:
    var rng: RandomNumberGenerator = _get_state_rng(state_id, base_rng)
    var total_weight: float = 0.0
    var prepared_options: Array[Dictionary] = []

    for option in options:
        var temperature: float = _resolve_temperature(model, state_id, option)
        var weight: float = float(option.get("weight", 1.0))
        if temperature != 1.0:
            weight = pow(weight, 1.0 / temperature)

        total_weight += weight
        prepared_options.append({
            "data": option,
            "weight": weight,
        })

    if total_weight <= 0.0:
        return _make_error(
            "non_positive_weight_sum",
            "Transition weights for state '%s' sum to zero." % state_id,
            {"state": state_id},
        )

    var pick: float = rng.randf_range(0.0, total_weight)
    var accumulator: float = 0.0
    for item in prepared_options:
        accumulator += item["weight"]
        if pick <= accumulator:
            return item["data"]

    return prepared_options.back()["data"]

func _resolve_temperature(model: MarkovModelResource, state_id: String, option: Dictionary) -> float:
    if option.has("temperature"):
        return float(option["temperature"])

    if model.token_temperatures.has(state_id):
        return float(model.token_temperatures[state_id])

    return model.default_temperature

func _get_state_rng(state_id: String, base_rng: RandomNumberGenerator) -> RandomNumberGenerator:
    if _state_rngs.has(state_id):
        return _state_rngs[state_id]

    var rng := RandomNumberGenerator.new()
    rng.seed = base_rng.randi()
    _state_rngs[state_id] = rng
    return rng

func describe() -> Dictionary:
    var notes := PackedStringArray([
        "markov_model_path must reference a MarkovModelResource asset.",
        "max_length guards against runaway generation when transitions never reach an end token.",
        "Model weights and temperatures influence token selection and can be tweaked per state.",
    ])
    return {
        "expected_config": get_config_schema(),
        "notes": notes,
    }
