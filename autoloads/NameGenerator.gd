extends Node
class_name NameGenerator

## Streams created through the RNG manager use this prefix when callers do not
## request a custom stream name.
const DEFAULT_STREAM_PREFIX := "name_generator"

## Registry of strategy instances keyed by their identifier.
var _strategies: Dictionary = {}

func _ready() -> void:
    """Register any built-in strategies once the autoload is ready."""
    _register_builtin_strategies()

func register_strategy(strategy_id: String, strategy: GeneratorStrategy) -> void:
    """Register ``strategy`` under ``strategy_id``.

    The helper can be used by gameplay code or editor tools to provide custom
    generation behaviour. When the provided ``strategy_id`` already exists it
    will be replaced and a warning is emitted so callers know an override
    occurred.
    """
    var normalized_id := _normalize_strategy_id(strategy_id)
    if normalized_id.is_empty():
        push_error("Strategy identifiers must be non-empty strings.")
        return

    if strategy == null:
        push_error("A GeneratorStrategy instance must be supplied when registering '%s'." % normalized_id)
        return

    if not (strategy is GeneratorStrategy):
        push_error("Strategy '%s' must inherit from GeneratorStrategy." % normalized_id)
        return

    if _strategies.has(normalized_id):
        push_warning("Overriding existing strategy '%s'." % normalized_id)

    _strategies[normalized_id] = strategy

func unregister_strategy(strategy_id: String) -> void:
    """Remove a previously registered strategy.

    When the strategy is not present the request is ignored. This makes it safe
    for callers to attempt cleanup without tracking registration state.
    """
    var normalized_id := _normalize_strategy_id(strategy_id)
    if normalized_id.is_empty():
        return

    _strategies.erase(normalized_id)

func has_strategy(strategy_id: String) -> bool:
    return _strategies.has(_normalize_strategy_id(strategy_id))

func list_strategies() -> PackedStringArray:
    var ids := PackedStringArray()
    for key in _strategies.keys():
        ids.append(String(key))
    ids.sort()
    return ids

func generate(config: Variant) -> Variant:
    var validation_error := _validate_request_config(config)
    if validation_error:
        return validation_error

    var request: Dictionary = config
    var strategy_id := _normalize_strategy_id(request["strategy"])
    var strategy: GeneratorStrategy = _strategies.get(strategy_id, null)
    if strategy == null:
        return _make_error("unknown_strategy", "Strategy '%s' is not registered." % strategy_id, {"strategy": strategy_id})

    var seed_info := _parse_seed(request)
    if seed_info.has("error") and seed_info["error"] != null:
        return seed_info["error"]

    var stream_name := _resolve_stream_name(request, strategy_id, seed_info)
    var rng_result := _obtain_rng(stream_name, seed_info)
    if rng_result.has("error") and rng_result["error"] != null:
        return rng_result["error"]

    var strategy_config := _extract_strategy_config(request)
    var result := strategy.generate(strategy_config, rng_result["rng"])

    if result is GeneratorStrategy.GeneratorError:
        return result.to_dict()

    if result is Dictionary:
        return result

    if typeof(result) != TYPE_STRING:
        return _make_error(
            "invalid_strategy_response",
            "Strategy '%s' returned an unsupported result type." % strategy_id,
            {
                "strategy": strategy_id,
                "returned_type": typeof(result),
                "type_name": Variant.get_type_name(typeof(result)),
            },
        )

    return result

func _register_builtin_strategies() -> void:
    var builtins := _get_builtin_strategy_map()
    for entry in builtins.keys():
        var strategy: GeneratorStrategy = builtins[entry]
        if strategy != null:
            register_strategy(entry, strategy)

func _get_builtin_strategy_map() -> Dictionary:
    return {}

func _normalize_strategy_id(value: Variant) -> String:
    if typeof(value) != TYPE_STRING:
        return ""
    return String(value).strip_edges()

func _validate_request_config(config: Variant) -> Dictionary:
    if typeof(config) != TYPE_DICTIONARY:
        return _make_error(
            "invalid_config_type",
            "NameGenerator.generate expects a Dictionary configuration.",
            {
                "received_type": typeof(config),
                "type_name": Variant.get_type_name(typeof(config)),
            },
        )

    var dictionary: Dictionary = config
    if not dictionary.has("strategy"):
        return _make_error("missing_strategy", "Configuration must include a 'strategy' key.")

    var normalized_id := _normalize_strategy_id(dictionary["strategy"])
    if normalized_id.is_empty():
        return _make_error(
            "invalid_strategy_identifier",
            "Strategy identifiers must be non-empty strings.",
        )

    if dictionary.has("rng_stream") and typeof(dictionary["rng_stream"]) != TYPE_STRING:
        return _make_error(
            "invalid_stream_name",
            "The 'rng_stream' override must be a string when provided.",
            {
                "received_type": typeof(dictionary["rng_stream"]),
                "type_name": Variant.get_type_name(typeof(dictionary["rng_stream"])),
            },
        )

    return null

func _parse_seed(config: Dictionary) -> Dictionary:
    var result := {
        "has_seed": false,
        "seed": 0,
        "error": null,
    }

    if not config.has("seed"):
        return result

    var seed_value := config["seed"]
    if typeof(seed_value) != TYPE_INT:
        result["error"] = _make_error(
            "invalid_seed_type",
            "Seed values must be integers when provided.",
            {
                "received_type": typeof(seed_value),
                "type_name": Variant.get_type_name(typeof(seed_value)),
            },
        )
        return result

    result["has_seed"] = true
    result["seed"] = int(seed_value)
    return result

func _resolve_stream_name(config: Dictionary, strategy_id: String, seed_info: Dictionary) -> String:
    if config.has("rng_stream"):
        return String(config["rng_stream"])

    if seed_info["has_seed"]:
        return "%s_%s_%s" % [DEFAULT_STREAM_PREFIX, strategy_id, String.num_int64(seed_info["seed"])]

    return "%s_%s" % [DEFAULT_STREAM_PREFIX, strategy_id]

func _obtain_rng(stream_name: String, seed_info: Dictionary) -> Dictionary:
    var response := {
        "rng": null,
        "error": null,
    }

    var rng: RandomNumberGenerator = null
    if Engine.has_singleton("RNGManager"):
        var manager := Engine.get_singleton("RNGManager")
        if manager != null and manager.has_method("get_rng"):
            if seed_info["has_seed"]:
                rng = manager.call("get_rng", stream_name, seed_info["seed"])
            else:
                rng = manager.call("get_rng", stream_name)
        elif manager != null and manager.has_method("request_rng"):
            if seed_info["has_seed"]:
                rng = manager.call("request_rng", stream_name, seed_info["seed"])
            else:
                rng = manager.call("request_rng", stream_name)

    if rng == null:
        rng = RandomNumberGenerator.new()
        if seed_info["has_seed"]:
            rng.seed = seed_info["seed"]
        else:
            rng.randomize()

    if not (rng is RandomNumberGenerator):
        response["error"] = _make_error(
            "invalid_rng_instance",
            "RNGManager returned an unexpected object for stream '%s'." % stream_name,
            {
                "stream": stream_name,
                "received_type": typeof(rng),
                "type_name": Variant.get_type_name(typeof(rng)),
            },
        )
        return response

    response["rng"] = rng
    return response

func _extract_strategy_config(config: Dictionary) -> Dictionary:
    var strategy_config := {}
    for key in config.keys():
        match key:
            "strategy", "seed", "rng_stream":
                pass
            _:
                strategy_config[key] = config[key]
    return strategy_config

func _make_error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
    return {
        "code": code,
        "message": message,
        "details": details.duplicate(true),
    }
