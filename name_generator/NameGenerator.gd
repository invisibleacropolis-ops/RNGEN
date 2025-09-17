extends Node
class_name NameGenerator

## High-level façade that coordinates the different generation strategies.
## The singleton is registered as a Godot autoload so game code and editor
## tooling can request names via a consistent API.

const DEFAULT_STREAM_PREFIX := "name_generator"

const GeneratorStrategy := preload("res://name_generator/strategies/GeneratorStrategy.gd")
const WordlistStrategy := preload("res://name_generator/strategies/WordlistStrategy.gd")
const SyllableChainStrategy := preload("res://name_generator/strategies/SyllableChainStrategy.gd")
const TemplateStrategy := preload("res://name_generator/strategies/TemplateStrategy.gd")
const MarkovChainStrategy := preload("res://name_generator/strategies/MarkovChainStrategy.gd")
const HybridStrategy := preload("res://name_generator/strategies/HybridStrategy.gd")
const ArrayUtils := preload("res://name_generator/utils/ArrayUtils.gd")
const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")

var _strategies: Dictionary = {}
var _debug_rng: DebugRNG = null

func _ready() -> void:
    _register_builtin_strategies()

func pick_from_list(options: Array, stream_name: String = "utility_name_list") -> Variant:
    ArrayUtils.assert_not_empty(options, "Name options")
    var rng := _acquire_rng(stream_name)
    return ArrayUtils.pick_uniform(options, rng)

func pick_weighted(entries: Array, stream_name: String = "utility_name_weighted") -> Variant:
    ArrayUtils.assert_not_empty(entries, "Weighted name entries")
    var rng := _acquire_rng(stream_name)
    return ArrayUtils.pick_weighted(entries, rng)

func register_strategy(strategy_id: String, strategy: GeneratorStrategy) -> void:
    var normalized := _normalize_strategy_id(strategy_id)
    if normalized.is_empty():
        push_error("Strategy identifiers must be non-empty strings.")
        return

    if strategy == null:
        push_error("Strategy '%s' must reference a valid GeneratorStrategy instance." % normalized)
        return

    if not (strategy is GeneratorStrategy):
        push_error("Strategy '%s' must extend GeneratorStrategy." % normalized)
        return

    _strategies[normalized] = strategy
    _maybe_track_strategy_with_debug(normalized, strategy)

func unregister_strategy(strategy_id: String) -> void:
    var normalized := _normalize_strategy_id(strategy_id)
    if normalized.is_empty():
        return
    if _strategies.has(normalized):
        _maybe_untrack_strategy_with_debug(_strategies[normalized])
    _strategies.erase(normalized)

func has_strategy(strategy_id: String) -> bool:
    return _strategies.has(_normalize_strategy_id(strategy_id))

func list_strategies() -> PackedStringArray:
    var result := PackedStringArray()
    for key in _strategies.keys():
        result.append(String(key))
    result.sort()
    return result

func describe_strategy(strategy_id: String) -> Dictionary:
    var normalized := _normalize_strategy_id(strategy_id)
    if normalized.is_empty():
        return {}

    var strategy: GeneratorStrategy = _strategies.get(normalized, null)
    if strategy == null:
        return {}

    var description := {}
    if strategy.has_method("describe"):
        var candidate := strategy.call("describe")
        if candidate is Dictionary:
            description = (candidate as Dictionary).duplicate(true)

    if description.is_empty():
        description = {}

    if not description.has("expected_config"):
        if strategy.has_method("get_config_schema"):
            var schema := strategy.call("get_config_schema")
            description["expected_config"] = schema.duplicate(true) if schema is Dictionary else {}
        else:
            description["expected_config"] = strategy._get_expected_config_keys().duplicate(true)

    if not description.has("id"):
        description["id"] = normalized

    if not description.has("display_name"):
        description["display_name"] = _format_strategy_display_name(normalized)

    return description

func describe_strategies() -> Dictionary:
    var descriptions := {}
    var identifiers := list_strategies()
    for identifier in identifiers:
        descriptions[identifier] = describe_strategy(identifier)
    return descriptions

func generate(config: Variant, override_rng: RandomNumberGenerator = null) -> Variant:
    var validation_error := _validate_request_config(config, override_rng != null)
    if validation_error:
        return validation_error

    var request: Dictionary = config
    var strategy_id := _normalize_strategy_id(request["strategy"])
    var strategy: GeneratorStrategy = _strategies.get(strategy_id, null)
    if strategy == null:
        return _make_error(
            "unknown_strategy",
            "Strategy '%s' is not registered." % strategy_id,
            {"strategy": strategy_id},
        )

    var stream_name := _resolve_stream_name(request, strategy_id)
    var rng := override_rng if override_rng != null else _acquire_rng(stream_name)

    var strategy_config := _extract_strategy_config(request)
    var result := strategy.generate(strategy_config, rng)

    if result is GeneratorStrategy.GeneratorError:
        return result.to_dict()

    return result

func _register_builtin_strategies() -> void:
    var builtins := _get_builtin_strategy_map()
    for identifier in builtins.keys():
        register_strategy(identifier, builtins[identifier])

func _get_builtin_strategy_map() -> Dictionary:
    return {
        "wordlist": WordlistStrategy.new(),
        "syllable": SyllableChainStrategy.new(),
        "template": TemplateStrategy.new(),
        "markov": MarkovChainStrategy.new(),
        "hybrid": HybridStrategy.new(),
    }

func _normalize_strategy_id(value: Variant) -> String:
    if typeof(value) != TYPE_STRING:
        return ""
    return String(value).strip_edges()

func _validate_request_config(config: Variant, allow_missing_seed: bool) -> Dictionary:
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

    if not allow_missing_seed and not dictionary.has("seed"):
        return _make_error("missing_seed", "Configuration must include a 'seed' value.")

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

func _resolve_stream_name(config: Dictionary, strategy_id: String) -> String:
    if config.has("rng_stream"):
        var provided := String(config["rng_stream"])
        _record_stream_usage(provided, strategy_id, config.get("seed", null), "explicit_config_override")
        return provided

    if config.has("seed"):
        var seed_string := String(config["seed"]).strip_edges()
        if seed_string.is_empty():
            seed_string = "seed"
        var seeded := "%s::%s" % [strategy_id, seed_string]
        _record_stream_usage(seeded, strategy_id, config.get("seed", null), "seed_derived")
        return seeded

    var fallback := "%s::%s" % [DEFAULT_STREAM_PREFIX, strategy_id]
    _record_stream_usage(fallback, strategy_id, config.get("seed", null), "default_prefix")
    return fallback

func _extract_strategy_config(config: Dictionary) -> Dictionary:
    var strategy_config := {}
    for key in config.keys():
        match key:
            "strategy", "rng_stream":
                pass
            _:
                strategy_config[key] = config[key]
    return strategy_config

func _acquire_rng(stream_name: String) -> RandomNumberGenerator:
    if Engine.has_singleton("RNGManager"):
        var manager := Engine.get_singleton("RNGManager")
        if manager != null and manager.has_method("get_rng"):
            var rng := manager.call("get_rng", stream_name)
            if rng is RandomNumberGenerator:
                return rng

    var fallback := RandomNumberGenerator.new()
    fallback.randomize()
    _record_stream_usage(stream_name, "", null, "fallback_rng_randomize")
    return fallback

func set_debug_rng(debug_rng: DebugRNG) -> void:
    ## Allow tooling to inject a DebugRNG instance so strategy registration,
    ## stream derivations, and fallback behavior are documented in shared logs.
    if _debug_rng == debug_rng:
        return

    if _debug_rng != null:
        _debug_rng.clear_tracked_strategies()

    _debug_rng = debug_rng

    if _debug_rng == null:
        return

    for key in _strategies.keys():
        var strategy: GeneratorStrategy = _strategies[key]
        _maybe_track_strategy_with_debug(key, strategy)

func _maybe_track_strategy_with_debug(identifier: String, strategy: GeneratorStrategy) -> void:
    if _debug_rng == null or strategy == null:
        return
    if _debug_rng.has_method("track_strategy"):
        _debug_rng.track_strategy(identifier, strategy)

func _maybe_untrack_strategy_with_debug(strategy: GeneratorStrategy) -> void:
    if _debug_rng == null or strategy == null:
        return
    if _debug_rng.has_method("untrack_strategy"):
        _debug_rng.untrack_strategy(strategy)

func _record_stream_usage(stream_name: String, strategy_id: String, seed: Variant, source: String) -> void:
    if _debug_rng == null or not _debug_rng.has_method("record_stream_usage"):
        return
    if stream_name == "":
        return
    var context := {
        "strategy_id": strategy_id,
        "seed": seed,
        "source": source,
    }
    _debug_rng.record_stream_usage(stream_name, context)

func _format_strategy_display_name(identifier: String) -> String:
    if identifier.is_empty():
        return ""

    var segments := identifier.split("_", false)
    var parts := PackedStringArray()
    for segment in segments:
        if segment.is_empty():
            continue
        parts.append(segment.capitalize())
    if parts.is_empty():
        return identifier.capitalize()
    return " ".join(parts)

func _make_error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
    return {
        "code": code,
        "message": message,
        "details": details.duplicate(true),
    }
