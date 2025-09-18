extends Node
## Controller node that exposes RNGProcessor middleware APIs to the Platform GUI.
##
## The controller hides the Engine singleton lookups, proxies common middleware
## calls, and forwards RNGProcessor signals to the Platform GUI event bus so
## panels can subscribe without touching the autoload directly.

@export var event_bus_path: NodePath

var _rng_processor_override: Object = null
var _cached_rng_processor: Object = null
var _connected_processor: Object = null
var _event_bus_override: Object = null
var _cached_event_bus: Object = null
var _latest_generation_metadata: Dictionary = {}

func _ready() -> void:
    _refresh_event_bus()
    _refresh_rng_processor()
    _ensure_processor_connections()

func initialize_master_seed(seed_value: int) -> void:
    var processor := _get_rng_processor()
    if processor == null:
        push_warning("RNGProcessor singleton unavailable; initialize_master_seed skipped.")
        return
    if processor.has_method("initialize_master_seed"):
        processor.call("initialize_master_seed", seed_value)
    elif processor.has_method("set_master_seed"):
        processor.call("set_master_seed", seed_value)

func reset_master_seed() -> int:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("reset_master_seed"):
        push_warning("RNGProcessor singleton unavailable; returning default master seed value.")
        return 0
    var result: Variant = processor.call("reset_master_seed")
    return int(result)

func list_strategies() -> PackedStringArray:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("list_strategies"):
        return PackedStringArray()
    var strategies: Variant = processor.call("list_strategies")
    if strategies is PackedStringArray:
        return strategies
    var packed := PackedStringArray()
    if strategies is Array:
        for value in strategies:
            packed.append(String(value))
    return packed

func describe_strategies() -> Dictionary:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("describe_strategies"):
        return {}
    var payload: Variant = processor.call("describe_strategies")
    if payload is Dictionary:
        return (payload as Dictionary).duplicate(true)
    return {}

func generate(config: Variant, override_rng: RandomNumberGenerator = null) -> Variant:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("generate"):
        return {
            "code": "missing_rng_processor",
            "message": "RNGProcessor singleton unavailable; request cannot be processed.",
            "details": {},
        }
    return processor.call("generate", config, override_rng)

func set_debug_rng(debug_rng: Object, attach_to_debug: bool = true) -> void:
    var processor := _get_rng_processor()
    if processor == null:
        push_warning("RNGProcessor singleton unavailable; set_debug_rng skipped.")
        return
    if processor.has_method("set_debug_rng"):
        processor.call("set_debug_rng", debug_rng, attach_to_debug)

func get_debug_rng() -> Object:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("get_debug_rng"):
        return null
    return processor.call("get_debug_rng")

func get_latest_generation_metadata() -> Dictionary:
    return _latest_generation_metadata.duplicate(true)

func set_rng_processor_override(processor: Object) -> void:
    _rng_processor_override = processor
    _cached_rng_processor = null
    _connected_processor = null
    _ensure_processor_connections()

func clear_rng_processor_override() -> void:
    _rng_processor_override = null
    _cached_rng_processor = null
    _connected_processor = null
    _ensure_processor_connections()

func set_event_bus_override(event_bus: Object) -> void:
    _event_bus_override = event_bus
    _cached_event_bus = null
    _refresh_event_bus()

func clear_event_bus_override() -> void:
    _event_bus_override = null
    _cached_event_bus = null
    _refresh_event_bus()

func refresh_connections() -> void:
    _refresh_event_bus()
    _refresh_rng_processor()
    _ensure_processor_connections()

func _refresh_rng_processor() -> void:
    _cached_rng_processor = null

func _refresh_event_bus() -> void:
    _cached_event_bus = null

func _get_rng_processor() -> Object:
    if _rng_processor_override != null and _is_object_valid(_rng_processor_override):
        return _rng_processor_override
    if _cached_rng_processor != null and _is_object_valid(_cached_rng_processor):
        return _cached_rng_processor
    if Engine.has_singleton("RNGProcessor"):
        var candidate := Engine.get_singleton("RNGProcessor")
        if _is_object_valid(candidate) and candidate.has_method("generate"):
            _cached_rng_processor = candidate
            return _cached_rng_processor
    return null

func _get_event_bus() -> Object:
    if _event_bus_override != null and _is_object_valid(_event_bus_override):
        return _event_bus_override
    if _cached_event_bus != null and _is_object_valid(_cached_event_bus):
        return _cached_event_bus
    if event_bus_path != NodePath("") and has_node(event_bus_path):
        var node := get_node(event_bus_path)
        if node != null:
            _cached_event_bus = node
            return _cached_event_bus
    if Engine.has_singleton("PlatformGUIEventBus"):
        var singleton := Engine.get_singleton("PlatformGUIEventBus")
        if _is_object_valid(singleton):
            _cached_event_bus = singleton
            return _cached_event_bus
    return null

func _ensure_processor_connections() -> void:
    var processor := _get_rng_processor()
    if processor == null:
        return
    _connect_processor_signal(processor, "generation_started", Callable(self, "_on_generation_started"))
    _connect_processor_signal(processor, "generation_completed", Callable(self, "_on_generation_completed"))
    _connect_processor_signal(processor, "generation_failed", Callable(self, "_on_generation_failed"))
    _connected_processor = processor

func _connect_processor_signal(processor: Object, signal_name: String, callable: Callable) -> void:
    if not processor.has_signal(signal_name):
        return
    if processor.is_connected(signal_name, callable):
        return
    processor.connect(signal_name, callable, CONNECT_REFERENCE_COUNTED)

func _on_generation_started(config: Dictionary, metadata: Dictionary) -> void:
    _latest_generation_metadata = metadata.duplicate(true)
    var payload: Dictionary = {
        "type": "generation_started",
        "config": _duplicate_variant(config),
        "metadata": _latest_generation_metadata.duplicate(true),
        "timestamp": Time.get_ticks_msec(),
    }
    _publish_event("rng_generation_started", payload)

func _on_generation_completed(config: Dictionary, result: Variant, metadata: Dictionary) -> void:
    _latest_generation_metadata = metadata.duplicate(true)
    var payload: Dictionary = {
        "type": "generation_completed",
        "config": _duplicate_variant(config),
        "result": _duplicate_variant(result),
        "metadata": _latest_generation_metadata.duplicate(true),
        "timestamp": Time.get_ticks_msec(),
    }
    _publish_event("rng_generation_completed", payload)

func _on_generation_failed(config: Dictionary, error: Dictionary, metadata: Dictionary) -> void:
    _latest_generation_metadata = metadata.duplicate(true)
    var payload: Dictionary = {
        "type": "generation_failed",
        "config": _duplicate_variant(config),
        "error": _duplicate_variant(error),
        "metadata": _latest_generation_metadata.duplicate(true),
        "timestamp": Time.get_ticks_msec(),
    }
    _publish_event("rng_generation_failed", payload)

func _publish_event(event_name: String, payload: Dictionary) -> void:
    var bus := _get_event_bus()
    if bus == null:
        return
    if bus.has_method("publish"):
        bus.call("publish", event_name, payload.duplicate(true))
        return
    if bus.has_signal("event_published"):
        bus.emit_signal("event_published", event_name, payload.duplicate(true))

func _duplicate_variant(value: Variant) -> Variant:
    if value is Dictionary:
        return (value as Dictionary).duplicate(true)
    if value is Array:
        return (value as Array).duplicate(true)
    return value

func _is_object_valid(candidate: Object) -> bool:
    if candidate == null:
        return false
    if candidate is Node:
        return is_instance_valid(candidate)
    return true
