extends Node

## Singleton-style service that caches RNG strategy metadata for the Platform GUI.
##
## The service proxies metadata requests through the RNGProcessor controller so the
## GUI can avoid touching engine singletons directly. Responses are cached until a
## manual refresh is requested, and helper methods expose normalised schema data so
## editor forms can render consistent constraints and hints.

@export var controller_path: NodePath

var _controller_override: Object = null
var _cached_controller: Object = null
var _metadata_cache: Dictionary = {}
var _has_loaded_cache: bool = false

const _SHARED_BASE_HINTS := {
    "invalid_config_type": "Configuration must be provided as a Dictionary.",
    "missing_required_keys": "Ensure required configuration keys are provided.",
    "invalid_key_type": "Optional configuration values must match their expected types.",
    "missing_resource": "Verify referenced resources exist at the configured paths.",
}

func _ready() -> void:
    _refresh_controller()

func set_controller_override(controller: Object) -> void:
    _controller_override = controller
    _cached_controller = null
    _clear_cache()

func clear_controller_override() -> void:
    _controller_override = null
    _cached_controller = null
    _clear_cache()

func refresh_controller() -> void:
    _refresh_controller()

func refresh_metadata() -> Dictionary:
    _clear_cache()
    return _ensure_metadata_loaded()

func get_strategy_ids() -> PackedStringArray:
    _ensure_metadata_loaded()
    var identifiers := PackedStringArray()
    for key in _metadata_cache.keys():
        identifiers.append(String(key))
    identifiers.sort()
    return identifiers

func get_strategy_metadata(strategy_id: String) -> Dictionary:
    _ensure_metadata_loaded()
    var key := _normalize_strategy_id(strategy_id)
    if key == "" or not _metadata_cache.has(key):
        return {}
    var entry: Dictionary = _metadata_cache[key]
    return (entry.get("description", {}) as Dictionary).duplicate(true)

func get_required_keys(strategy_id: String) -> PackedStringArray:
    _ensure_metadata_loaded()
    var key := _normalize_strategy_id(strategy_id)
    if key == "" or not _metadata_cache.has(key):
        return PackedStringArray()
    var entry: Dictionary = _metadata_cache[key]
    var required: PackedStringArray = entry.get("required_keys", PackedStringArray())
    return required.duplicate()

func get_optional_key_types(strategy_id: String) -> Dictionary:
    _ensure_metadata_loaded()
    var key := _normalize_strategy_id(strategy_id)
    if key == "" or not _metadata_cache.has(key):
        return {}
    var entry: Dictionary = _metadata_cache[key]
    var optional: Dictionary = entry.get("optional_key_types", {})
    return _duplicate_dictionary(optional)

func get_default_notes(strategy_id: String) -> PackedStringArray:
    _ensure_metadata_loaded()
    var key := _normalize_strategy_id(strategy_id)
    if key == "" or not _metadata_cache.has(key):
        return PackedStringArray()
    var entry: Dictionary = _metadata_cache[key]
    var notes: PackedStringArray = entry.get("notes", PackedStringArray())
    return notes.duplicate()

func get_generator_error_hints(strategy_id: String) -> Dictionary:
    _ensure_metadata_loaded()
    var key := _normalize_strategy_id(strategy_id)
    if key == "" or not _metadata_cache.has(key):
        return _SHARED_BASE_HINTS.duplicate()
    var entry: Dictionary = _metadata_cache[key]
    var hints: Dictionary = entry.get("error_hints", {})
    var merged := _SHARED_BASE_HINTS.duplicate(true)
    for hint_code in hints.keys():
        merged[hint_code] = hints[hint_code]
    return merged

func get_generator_error_hint(strategy_id: String, code: String) -> String:
    var hints := get_generator_error_hints(strategy_id)
    return String(hints.get(code, ""))

func _ensure_metadata_loaded() -> Dictionary:
    if _has_loaded_cache:
        return _metadata_cache.duplicate(true)

    _metadata_cache.clear()
    var controller := _get_controller()
    if controller != null and controller.has_method("describe_strategies"):
        var payload: Variant = controller.call("describe_strategies")
        if payload is Dictionary:
            var descriptions: Dictionary = payload
            for raw_key in descriptions.keys():
                var normalized := _normalize_strategy_id(raw_key)
                if normalized == "":
                    continue

                var description_variant: Variant = descriptions[raw_key]
                if not (description_variant is Dictionary):
                    continue

                var description: Dictionary = (description_variant as Dictionary).duplicate(true)
                if not description.has("id"):
                    description["id"] = normalized

                var required_keys := _extract_required_keys(description)
                var optional_key_types := _extract_optional_key_types(description)
                var notes := _extract_notes(description)
                var error_hints := _build_error_hints(required_keys, optional_key_types)

                _metadata_cache[normalized] = {
                    "description": description,
                    "required_keys": required_keys,
                    "optional_key_types": optional_key_types,
                    "notes": notes,
                    "error_hints": error_hints,
                }

    _has_loaded_cache = true
    return _metadata_cache.duplicate(true)

func _refresh_controller() -> void:
    _cached_controller = null

func _clear_cache() -> void:
    _metadata_cache.clear()
    _has_loaded_cache = false

func _get_controller() -> Object:
    if _controller_override != null and _is_object_valid(_controller_override):
        return _controller_override
    if _cached_controller != null and _is_object_valid(_cached_controller):
        return _cached_controller
    if controller_path != NodePath("") and has_node(controller_path):
        var node := get_node(controller_path)
        if node != null:
            _cached_controller = node
            return _cached_controller
    if Engine.has_singleton("RNGProcessorController"):
        var singleton := Engine.get_singleton("RNGProcessorController")
        if _is_object_valid(singleton):
            _cached_controller = singleton
            return _cached_controller
    return null

func _normalize_strategy_id(value: Variant) -> String:
    if typeof(value) != TYPE_STRING:
        return ""
    return String(value).strip_edges()

func _extract_required_keys(description: Dictionary) -> PackedStringArray:
    var expected_variant: Variant = description.get("expected_config", {})
    if not (expected_variant is Dictionary):
        return PackedStringArray()

    var expected: Dictionary = expected_variant
    var required_variant: Variant = expected.get("required", PackedStringArray())
    var normalized := PackedStringArray()

    if required_variant is PackedStringArray:
        normalized = (required_variant as PackedStringArray).duplicate()
    elif required_variant is Array:
        for value in required_variant:
            normalized.append(String(value))

    normalized.sort()
    return normalized

func _extract_optional_key_types(description: Dictionary) -> Dictionary:
    var expected_variant: Variant = description.get("expected_config", {})
    if not (expected_variant is Dictionary):
        return {}

    var expected: Dictionary = expected_variant
    var optional_variant: Variant = expected.get("optional", {})
    if not (optional_variant is Dictionary):
        return {}

    var optional: Dictionary = {}
    for key in optional_variant.keys():
        var type_value: Variant = optional_variant[key]
        optional[String(key)] = int(type_value)

    return optional

func _extract_notes(description: Dictionary) -> PackedStringArray:
    var notes_variant: Variant = description.get("notes", PackedStringArray())
    if notes_variant is PackedStringArray:
        return (notes_variant as PackedStringArray).duplicate()
    var notes := PackedStringArray()
    if notes_variant is Array:
        for value in notes_variant:
            notes.append(String(value))
    return notes

func _build_error_hints(required_keys: PackedStringArray, optional_key_types: Dictionary) -> Dictionary:
    var hints: Dictionary = {}

    if required_keys.size() > 0:
        hints["missing_required_keys"] = "Include required keys: %s." % ", ".join(required_keys)
    else:
        hints["missing_required_keys"] = "Ensure required configuration keys are provided."

    if optional_key_types.size() > 0:
        var segments: Array[String] = []
        var keys := optional_key_types.keys()
        keys.sort()
        for key in keys:
            var expected_type: int = int(optional_key_types[key])
            segments.append("%s (%s)" % [String(key), type_string(expected_type)])
        hints["invalid_key_type"] = "Optional keys must use expected types such as %s." % ", ".join(segments)
    else:
        hints["invalid_key_type"] = "Optional configuration values must match their expected types."

    return hints

func _duplicate_dictionary(value: Dictionary) -> Dictionary:
    var clone: Dictionary = {}
    for key in value.keys():
        clone[key] = value[key]
    return clone
