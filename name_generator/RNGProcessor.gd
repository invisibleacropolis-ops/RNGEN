extends Node

## Middleware singleton that coordinates NameGenerator requests and RNGManager
## seed management. The processor exposes a narrow API designed for editor tools
## and gameplay systems that need deterministic name generation plus
## observability hooks around each request.

signal generation_started(request_config: Dictionary, metadata: Dictionary)
signal generation_completed(request_config: Dictionary, result: Variant, metadata: Dictionary)
signal generation_failed(request_config: Dictionary, error: Dictionary, metadata: Dictionary)

const NameGeneratorScript := preload("res://name_generator/NameGenerator.gd")
const RNGManagerScript := preload("res://name_generator/RNGManager.gd")
const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")
const RNGStreamRouter := preload("res://name_generator/utils/RNGManager.gd")

var _name_generator: Object = null
var _rng_manager: Object = null
var _fallback_master_seed: int = 0
var _fallback_streams: Dictionary = {}
var _debug_rng: DebugRNG = null

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
        var router: RNGStreamRouter = _build_router_for_stream(_fallback_master_seed, key)
        var rng := router.to_rng()
        _fallback_streams[key] = rng
    return _fallback_streams[key]

func describe_rng_streams() -> Dictionary:
    ## Provide a snapshot of the active RNG topology. When RNGManager is
    ## available the method proxies its `save_state()` payload so tooling can
    ## inspect live stream seeds. In fallback mode we expose the locally cached
    ## streams derived from RNGStreamRouter semantics, mirroring how
    ## `get_rng(...)` hashes stream paths.
    var payload: Dictionary = {
        "mode": "rng_manager",
        "master_seed": get_master_seed(),
        "streams": {},
    }

    var manager := _get_rng_manager()
    if manager != null and manager.has_method("save_state"):
        var state_payload: Variant = manager.call("save_state")
        if state_payload is Dictionary:
            var state_dict: Dictionary = state_payload
            var streams_payload: Variant = state_dict.get("streams", {})
            if streams_payload is Dictionary:
                for stream_name in streams_payload.keys():
                    var name := String(stream_name)
                    payload["streams"][name] = _normalise_stream_payload(streams_payload[stream_name])
            return payload

    payload["mode"] = "fallback"
    for stream_name in _fallback_streams.keys():
        var rng: RandomNumberGenerator = _fallback_streams[stream_name]
        payload["streams"][String(stream_name)] = {
            "seed": int(rng.seed),
            "state": int(rng.state),
            "path": _build_fallback_path(String(stream_name)),
        }
    return payload

func describe_stream_routing(stream_names: PackedStringArray = PackedStringArray()) -> Dictionary:
    ## Summarise how RNG streams are derived from the master seed. The response
    ## mirrors RNGStreamRouter semantics so UI tooling can render routing trees
    ## and explain fallback behaviour when RNGManager is unavailable.
    var topology := describe_rng_streams()
    var routes: Array = []
    var master_seed := int(topology.get("master_seed", 0))
    var observed_streams: Dictionary = topology.get("streams", {})

    var names: Array = []
    if stream_names.is_empty():
        for key in observed_streams.keys():
            names.append(String(key))
    else:
        for value in stream_names:
            names.append(String(value))

    names.sort()

    for stream_name in names:
        var path := _build_fallback_path(stream_name)
        var router: RNGStreamRouter = _build_router_for_stream(master_seed, stream_name)
        var derived_rng := router.to_rng()
        var stream_info: Dictionary = observed_streams.get(stream_name, {})
        var route: Dictionary = {
            "stream": stream_name,
            "path": path,
            "derived_seed": int(derived_rng.seed),
            "derived_state": int(derived_rng.state),
        }
        if stream_info.has("seed"):
            route["resolved_seed"] = int(stream_info["seed"])
        if stream_info.has("state"):
            route["resolved_state"] = int(stream_info["state"])
        if stream_info.has("path"):
            route["fallback_path"] = stream_info["path"]
        routes.append(route)

    var notes: Array = []
    if topology.get("mode", "rng_manager") == "fallback":
        notes.append("RNGManager unavailable; fallback streams derive deterministic seeds via RNGStreamRouter using the listed path segments.")
    else:
        notes.append("RNGManager authoritative; router preview illustrates the deterministic path used when replaying streams in tools.")

    return {
        "mode": topology.get("mode", "rng_manager"),
        "master_seed": master_seed,
        "routes": routes,
        "notes": notes,
    }

func export_rng_state() -> Dictionary:
    ## Serialize the current seed topology so it can be imported later. The
    ## payload mirrors `RNGManager.save_state()` when the singleton is
    ## available, falling back to the processor's cached streams in isolated
    ## environments.
    var manager := _get_rng_manager()
    if manager != null and manager.has_method("save_state"):
        var state_payload: Variant = manager.call("save_state")
        if state_payload is Dictionary:
            return (state_payload as Dictionary).duplicate(true)

    var exported_streams: Dictionary = {}
    for stream_name in _fallback_streams.keys():
        var rng: RandomNumberGenerator = _fallback_streams[stream_name]
        exported_streams[String(stream_name)] = {
            "seed": int(rng.seed),
            "state": int(rng.state),
        }

    return {
        "master_seed": _fallback_master_seed,
        "streams": exported_streams,
    }

func import_rng_state(payload: Variant) -> void:
    ## Restore a previously exported seed topology. The call proxies
    ## `RNGManager.load_state(...)` when possible and otherwise hydrates the
    ## fallback caches maintained by the processor.
    var manager := _get_rng_manager()
    if manager != null and manager.has_method("load_state"):
        manager.call("load_state", payload)
        _fallback_master_seed = int(manager.call("get_master_seed"))
        _fallback_streams.clear()
        return

    if typeof(payload) != TYPE_DICTIONARY:
        push_warning("RNGProcessor.import_rng_state expected a Dictionary payload when RNGManager is unavailable.")
        return

    var data: Dictionary = payload
    _fallback_master_seed = int(data.get("master_seed", 0))
    _fallback_streams.clear()

    var streams_payload: Variant = data.get("streams", {})
    if streams_payload is Dictionary:
        for stream_name in streams_payload.keys():
            var name := String(stream_name)
            var router: RNGStreamRouter = _build_router_for_stream(_fallback_master_seed, name)
            var rng := router.to_rng()
            var stream_state: Dictionary = _normalise_stream_payload(streams_payload[stream_name])
            rng.seed = int(stream_state.get("seed", rng.seed))
            rng.state = int(stream_state.get("state", rng.state))
            _fallback_streams[name] = rng

func list_strategies() -> PackedStringArray:
    ## Mirror NameGenerator.list_strategies so tooling can enumerate available
    ## options through the middleware without poking the generator directly.
    var generator := _get_name_generator()
    if generator != null and generator.has_method("list_strategies"):
        var result: Variant = generator.call("list_strategies")
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
        var description: Variant = generator.call("describe_strategy", strategy_id)
        if description is Dictionary:
            return (description as Dictionary).duplicate(true)
    return {}

func describe_strategies() -> Dictionary:
    ## Convenience accessor that returns the description payload for every
    ## registered strategy keyed by its identifier.
    var metadata: Dictionary = {}
    var strategies := list_strategies()
    for identifier in strategies:
        metadata[identifier] = describe_strategy(identifier)
    return metadata

func generate(config: Variant, override_rng: RandomNumberGenerator = null) -> Variant:
    ## Proxy NameGenerator.generate while emitting middleware events that expose
    ## execution metadata to interested observers.
    var generator := _get_name_generator()
    if generator == null or not generator.has_method("generate"):
        var error: Dictionary = {
            "code": "missing_name_generator",
            "message": "RNGProcessor requires the NameGenerator singleton to be available.",
            "details": {},
        }
        emit_signal("generation_failed", _duplicate_variant(config), error.duplicate(true), _build_generation_metadata(config, override_rng))
        return error

    var metadata: Dictionary = _build_generation_metadata(config, override_rng)
    emit_signal("generation_started", _duplicate_variant(config), metadata.duplicate(true))

    var result: Variant = generator.call("generate", config, override_rng)

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
            _propagate_debug_rng_to_generator()

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
    var metadata: Dictionary = {
        "strategy_id": "",
        "seed": null,
        "rng_stream": "",
    }

    if typeof(config) == TYPE_DICTIONARY:
        var dictionary: Dictionary = config
        var strategy_value: Variant = dictionary.get("strategy", "")
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
        var provided := String(config["rng_stream"])
        _record_debug_stream_usage(provided, strategy_id, config.get("seed", null), "explicit_config_override")
        return provided

    if override_rng != null:
        return ""

    if config.has("seed"):
        var seed_string := String(config["seed"]).strip_edges()
        if seed_string.is_empty():
            seed_string = "seed"
        var seeded := "%s::%s" % [strategy_id, seed_string]
        _record_debug_stream_usage(seeded, strategy_id, config.get("seed", null), "seed_derived")
        return seeded

    var fallback := "%s::%s" % [NameGeneratorScript.DEFAULT_STREAM_PREFIX, strategy_id]
    _record_debug_stream_usage(fallback, strategy_id, config.get("seed", null), "default_prefix")
    return fallback

func _duplicate_variant(value: Variant) -> Variant:
    if value is Dictionary:
        return (value as Dictionary).duplicate(true)
    if value is Array:
        return (value as Array).duplicate(true)
    return value

func set_debug_rng(debug_rng: DebugRNG, attach_to_debug: bool = true) -> void:
    ## Allow external tooling to register a DebugRNG observer for middleware
    ## events and stream derivations.
    if _debug_rng == debug_rng:
        return

    if _debug_rng != null and _debug_rng.has_method("detach_from_processor"):
        _debug_rng.detach_from_processor(self)

    _debug_rng = debug_rng

    if _debug_rng != null:
        if attach_to_debug and _debug_rng.has_method("attach_to_processor"):
            _debug_rng.attach_to_processor(self, DebugRNG.DEFAULT_LOG_PATH, false)
        _propagate_debug_rng_to_generator()
        return

    var generator := _get_name_generator()
    if generator != null and generator.has_method("set_debug_rng"):
        generator.call("set_debug_rng", null)

func get_debug_rng() -> DebugRNG:
    return _debug_rng

func _propagate_debug_rng_to_generator() -> void:
    if _debug_rng == null:
        return
    var generator := _get_name_generator()
    if generator != null and generator.has_method("set_debug_rng"):
        generator.call("set_debug_rng", _debug_rng)

func _record_debug_stream_usage(stream_name: String, strategy_id: String, seed: Variant, source: String) -> void:
    if _debug_rng == null or stream_name == "" or not _debug_rng.has_method("record_stream_usage"):
        return
    var context: Dictionary = {
        "strategy_id": strategy_id,
        "seed": seed,
        "source": source,
    }
    _debug_rng.record_stream_usage(stream_name, context)

func _normalise_stream_payload(payload: Variant) -> Dictionary:
    var result: Dictionary = {"seed": 0, "state": 0}
    if typeof(payload) in [TYPE_INT, TYPE_FLOAT]:
        var value := int(payload)
        result["seed"] = value
        result["state"] = value
        return result
    if payload is Dictionary:
        var data: Dictionary = payload
        if typeof(data.get("seed", null)) in [TYPE_INT, TYPE_FLOAT]:
            result["seed"] = int(data["seed"])
        if typeof(data.get("state", null)) in [TYPE_INT, TYPE_FLOAT]:
            result["state"] = int(data["state"])
        elif data.has("seed"):
            result["state"] = result["seed"]
    return result

func _build_router_for_stream(seed_value: int, stream_name: String) -> RNGStreamRouter:
    var key := stream_name if not stream_name.is_empty() else "default"
    var path := _build_fallback_path(key)
    return (RNGStreamRouter.new(seed_value, path) as RNGStreamRouter)

func _build_fallback_path(stream_name: String) -> PackedStringArray:
    var path := PackedStringArray()
    path.append("rng_processor")
    path.append(stream_name if not stream_name.is_empty() else "default")
    return path
