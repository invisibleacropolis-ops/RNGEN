extends Node
class_name RNGProcessor

## Middleware singleton that coordinates NameGenerator requests and RNGManager
## seed management. The processor exposes a narrow API designed for editor tools
## and gameplay systems that need deterministic name generation plus
## observability hooks around each request.

signal generation_started(request_config: Dictionary, metadata: Dictionary)
signal generation_completed(request_config: Dictionary, result: Variant, metadata: Dictionary)
signal generation_failed(request_config: Dictionary, error: Dictionary, metadata: Dictionary)

const NameGeneratorScript := preload("res://name_generator/NameGenerator.gd")
const RNGManagerScript := preload("res://name_generator/RNGManager.gd")

var _name_generator: Object = null
var _rng_manager: Object = null
var _fallback_master_seed: int = 0
var _fallback_streams: Dictionary = {}

func _ready() -> void:
    ## Capture singleton references once the node enters the scene tree.
    _refresh_singletons()

func initialize_master_seed(seed_value: int) -> void:
    ## Initialize the master seed used for all downstream RNG streams.
    _apply_master_seed(seed_value)

func reset_master_seed() -> int:
    ## Randomize the master seed and return the new value for bookkeeping.
    return randomize_master_seed()

func set_master_seed(seed_value: int) -> void:
    ## Explicit setter mirroring RNGManager's API for callers that prefer
    ## imperative naming. The call delegates to initialize_master_seed to avoid
    ## duplicating logic.
    _apply_master_seed(seed_value)

func randomize_master_seed() -> int:
    ## Derive a fresh master seed using Godot's RNG facilities and propagate the
    ## value to RNGManager when available. The method returns the new seed so the
    ## caller can persist or log it as needed.
    var manager := _get_rng_manager()
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var new_seed := int(rng.randi())
    if manager != null and manager.has_method("set_master_seed"):
        manager.call("set_master_seed", new_seed)
    _fallback_master_seed = new_seed
    _fallback_streams.clear()
    return new_seed

func get_master_seed() -> int:
    ## Expose the current master seed, falling back to the locally cached copy
    ## when RNGManager is unavailable (which primarily occurs in isolated unit
    ## tests).
    var manager := _get_rng_manager()
    if manager != null and manager.has_method("get_master_seed"):
        return int(manager.call("get_master_seed"))
    return _fallback_master_seed

func get_rng(stream_name: String) -> RandomNumberGenerator:
    ## Acquire a deterministic RNG stream from RNGManager or, when unavailable,
    ## from the processor's lightweight local implementation.
    var manager := _get_rng_manager()
    if manager != null and manager.has_method("get_rng"):
        return manager.call("get_rng", stream_name)

    var key := stream_name if not stream_name.is_empty() else "default"
    if not _fallback_streams.has(key):
        var rng := RandomNumberGenerator.new()
        var seed := int(hash("%s::%s" % [_fallback_master_seed, key]) & 0x7fffffffffffffff)
        rng.seed = seed
        rng.state = seed
        _fallback_streams[key] = rng
    return _fallback_streams[key]

func list_strategies() -> PackedStringArray:
    ## Mirror NameGenerator.list_strategies so tooling can enumerate available
    ## options through the middleware without poking the generator directly.
    var generator := _get_name_generator()
    if generator != null and generator.has_method("list_strategies"):
        var result := generator.call("list_strategies")
        if result is PackedStringArray:
            return result
        elif result is Array:
            var packed := PackedStringArray()
            for value in result:
                packed.append(String(value))
            return packed
    return PackedStringArray()

func describe_strategy(strategy_id: String) -> Dictionary:
    ## Fetch metadata describing a registered strategy, including its expected
    ## configuration schema and any human-readable notes the strategy exposes.
    var generator := _get_name_generator()
    if generator != null and generator.has_method("describe_strategy"):
        var description := generator.call("describe_strategy", strategy_id)
        if description is Dictionary:
            return (description as Dictionary).duplicate(true)
    return {}

func describe_strategies() -> Dictionary:
    ## Convenience accessor that returns the description payload for every
    ## registered strategy keyed by its identifier.
    var metadata := {}
    var strategies := list_strategies()
    for identifier in strategies:
        metadata[identifier] = describe_strategy(identifier)
    return metadata

func generate(config: Variant, override_rng: RandomNumberGenerator = null) -> Variant:
    ## Proxy NameGenerator.generate while emitting middleware events that expose
    ## execution metadata to interested observers.
    var generator := _get_name_generator()
    if generator == null or not generator.has_method("generate"):
        var error := {
            "code": "missing_name_generator",
            "message": "RNGProcessor requires the NameGenerator singleton to be available.",
            "details": {},
        }
        emit_signal("generation_failed", _duplicate_variant(config), error.duplicate(true), _build_generation_metadata(config, override_rng))
        return error

    var metadata := _build_generation_metadata(config, override_rng)
    emit_signal("generation_started", _duplicate_variant(config), metadata.duplicate(true))

    var result := generator.call("generate", config, override_rng)

    if result is Dictionary and result.has("code"):
        emit_signal("generation_failed", _duplicate_variant(config), (result as Dictionary).duplicate(true), metadata.duplicate(true))
    else:
        emit_signal("generation_completed", _duplicate_variant(config), result, metadata.duplicate(true))

    return result

func _apply_master_seed(seed_value: int) -> void:
    var manager := _get_rng_manager()
    if manager != null and manager.has_method("set_master_seed"):
        manager.call("set_master_seed", seed_value)
    _fallback_master_seed = seed_value
    _fallback_streams.clear()

func _refresh_singletons() -> void:
    _refresh_name_generator()
    _refresh_rng_manager()

func _refresh_name_generator() -> void:
    _name_generator = null
    if Engine.has_singleton("NameGenerator"):
        var candidate := Engine.get_singleton("NameGenerator")
        if candidate != null and candidate.has_method("generate"):
            _name_generator = candidate

func _refresh_rng_manager() -> void:
    _rng_manager = null
    if Engine.has_singleton("RNGManager"):
        var candidate := Engine.get_singleton("RNGManager")
        if candidate != null and candidate.has_method("get_rng"):
            _rng_manager = candidate

func _get_name_generator() -> Object:
    if _name_generator == null or not is_instance_valid(_name_generator):
        _refresh_name_generator()
    return _name_generator

func _get_rng_manager() -> Object:
    if _rng_manager == null or not is_instance_valid(_rng_manager):
        _refresh_rng_manager()
    return _rng_manager

func _build_generation_metadata(config: Variant, override_rng: RandomNumberGenerator) -> Dictionary:
    var metadata := {
        "strategy_id": "",
        "seed": null,
        "rng_stream": "",
    }

    if typeof(config) == TYPE_DICTIONARY:
        var dictionary: Dictionary = config
        var strategy_value := dictionary.get("strategy", "")
        var strategy_id := _normalize_strategy_id(strategy_value)
        metadata["strategy_id"] = strategy_id
        if dictionary.has("seed"):
            metadata["seed"] = dictionary.get("seed")
        metadata["rng_stream"] = _resolve_stream_name(dictionary, strategy_id, override_rng)

    return metadata

func _normalize_strategy_id(value: Variant) -> String:
    if typeof(value) != TYPE_STRING:
        return ""
    return String(value).strip_edges()

func _resolve_stream_name(
    config: Dictionary,
    strategy_id: String,
    override_rng: RandomNumberGenerator
) -> String:
    if config.has("rng_stream"):
        return String(config["rng_stream"])

    if override_rng != null:
        return ""

    if config.has("seed"):
        var seed_string := String(config["seed"]).strip_edges()
        if seed_string.is_empty():
            seed_string = "seed"
        return "%s::%s" % [strategy_id, seed_string]

    return "%s::%s" % [NameGeneratorScript.DEFAULT_STREAM_PREFIX, strategy_id]

func _duplicate_variant(value: Variant) -> Variant:
    if value is Dictionary:
        return (value as Dictionary).duplicate(true)
    if value is Array:
        return (value as Array).duplicate(true)
    return value
