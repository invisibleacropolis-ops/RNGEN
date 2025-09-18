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

const _HANDBOOK_SECTIONS := {
    "config": {
        "anchor": "middleware-errors-configuration",
        "label": "Configuration payloads",
    },
    "required_keys": {
        "anchor": "middleware-errors-required-keys",
        "label": "Required key mismatches",
    },
    "optional_keys": {
        "anchor": "middleware-errors-optional-types",
        "label": "Optional key typing",
    },
    "resources": {
        "anchor": "middleware-errors-resources",
        "label": "Resource lookups",
    },
    "wordlists": {
        "anchor": "middleware-errors-wordlists",
        "label": "Word list datasets",
    },
    "syllable_ranges": {
        "anchor": "middleware-errors-syllable-ranges",
        "label": "Syllable chain ranges",
    },
    "template": {
        "anchor": "middleware-errors-template-nesting",
        "label": "Template nesting",
    },
    "hybrid": {
        "anchor": "middleware-errors-hybrid-pipelines",
        "label": "Hybrid pipelines",
    },
    "markov": {
        "anchor": "middleware-errors-markov-models",
        "label": "Markov chain datasets",
    },
}

var _BASE_ERROR_GUIDE := _build_base_error_guide()

func _make_guidance(message: String, remediation: String, handbook_key: String = "") -> Dictionary:
    var entry := {
        "message": message,
        "remediation": remediation,
    }
    if handbook_key != "" and _HANDBOOK_SECTIONS.has(handbook_key):
        var section: Dictionary = _HANDBOOK_SECTIONS[handbook_key]
        entry["handbook_anchor"] = String(section.get("anchor", ""))
        entry["handbook_label"] = String(section.get("label", ""))
    return entry

func _build_base_error_guide() -> Dictionary:
    return {
        "invalid_config_type": _make_guidance(
            "Configuration payload must be provided as a Dictionary.",
            "Regenerate the payload from the GUI form or rebuild it using the Handbook configuration template.",
            "config",
        ),
        "missing_required_keys": _make_guidance(
            "Configuration is missing at least one required key.",
            "Compare your payload with the required key list documented in the handbook before retrying.",
            "required_keys",
        ),
        "invalid_key_type": _make_guidance(
            "Optional key value does not match the expected type.",
            "Confirm each optional key uses the type shown in the optional key reference table.",
            "optional_keys",
        ),
        "missing_resource": _make_guidance(
            "Referenced resource could not be loaded from disk.",
            "Verify the path, file extension, and import status against the resource checklist.",
            "resources",
        ),
        "invalid_resource_type": _make_guidance(
            "Loaded resource exists but does not match the expected type.",
            "Open the referenced file in Godot and confirm it inherits from the required resource class.",
            "resources",
        ),
        "invalid_wordlist_paths_type": _make_guidance(
            "'wordlist_paths' must contain resource paths or WordListResource instances.",
            "Select word lists through the GUI picker or mirror the array structure described in the handbook.",
            "wordlists",
        ),
        "invalid_wordlist_entry": _make_guidance(
            "Word list entries must be strings or WordListResource objects.",
            "Clean the array so only resource paths or preloaded resources remain before generating.",
            "wordlists",
        ),
        "wordlists_missing": _make_guidance(
            "No word list resources were provided to the strategy.",
            "Use the resource browser to add at least one dataset before generating.",
            "wordlists",
        ),
        "wordlists_no_selection": _make_guidance(
            "The configured word lists did not return any entries.",
            "Double-check that each word list contains entries and the filters match the handbook workflow.",
            "wordlists",
        ),
        "wordlist_invalid_type": _make_guidance(
            "Loaded resource is not a WordListResource.",
            "Confirm the path targets a `.tres` exported from the word list builder tools.",
            "wordlists",
        ),
        "wordlist_empty": _make_guidance(
            "Word list resource does not expose any entries.",
            "Populate the dataset via the builder and reimport before attempting another preview.",
            "wordlists",
        ),
        "invalid_syllable_set_path": _make_guidance(
            "'syllable_set_path' must be a valid resource path.",
            "Browse to an existing syllable set asset listed in the handbook inventory.",
            "syllable_ranges",
        ),
        "invalid_syllable_set_type": _make_guidance(
            "Loaded resource is not a SyllableSetResource.",
            "Rebuild the asset using the syllable set builder described in the handbook.",
            "syllable_ranges",
        ),
        "empty_prefixes": _make_guidance(
            "Selected syllable set is missing prefix entries.",
            "Edit the dataset so every required syllable column contains at least one entry.",
            "syllable_ranges",
        ),
        "empty_suffixes": _make_guidance(
            "Selected syllable set is missing suffix entries.",
            "Populate suffix data in the resource before generating again.",
            "syllable_ranges",
        ),
        "missing_required_middles": _make_guidance(
            "Configuration requires middle syllables but the resource has none.",
            "Add middle syllables to the dataset or disable the 'require_middle' option.",
            "syllable_ranges",
        ),
        "middle_syllables_not_available": _make_guidance(
            "Requested middle syllables but the resource does not define any.",
            "Reduce the middle syllable range or update the dataset with middle entries.",
            "syllable_ranges",
        ),
        "invalid_middle_range": _make_guidance(
            "'middle_syllables' must define a valid min/max range.",
            "Ensure min is less than or equal to max and matches the examples in the handbook.",
            "syllable_ranges",
        ),
        "unable_to_satisfy_min_length": _make_guidance(
            "Generated name could not reach the requested minimum length.",
            "Lower the minimum length or expand the syllable set to include longer fragments.",
            "syllable_ranges",
        ),
        "invalid_template_type": _make_guidance(
            "Template payload must be a string before tokens can be resolved.",
            "Copy the template examples directly from the handbook to restore the correct syntax.",
            "template",
        ),
        "empty_token": _make_guidance(
            "Template contains an empty token placeholder.",
            "Replace empty placeholders with named tokens so they can map to sub-generators.",
            "template",
        ),
        "missing_template_token": _make_guidance(
            "Template references a token that is not defined in sub_generators.",
            "Add a matching entry to the sub-generator dictionary following the handbook example.",
            "template",
        ),
        "invalid_sub_generators_type": _make_guidance(
            "sub_generators must be a Dictionary keyed by template tokens.",
            "Restructure the payload so each token maps to a configuration dictionary.",
            "template",
        ),
        "invalid_max_depth": _make_guidance(
            "max_depth must be a positive integer.",
            "Set max_depth using the defensive defaults outlined in the handbook.",
            "template",
        ),
        "missing_strategy": _make_guidance(
            "Sub-generator entry is missing its 'strategy' identifier.",
            "Assign a strategy id that matches the middleware catalog before generating.",
            "template",
        ),
        "template_recursion_depth_exceeded": _make_guidance(
            "Nested templates exceeded the configured max_depth.",
            "Increase max_depth or simplify nested calls per the handbook escalation steps.",
            "template",
        ),
        "invalid_name_generator_resource": _make_guidance(
            "Fallback NameGenerator resource is not a valid GDScript.",
            "Point the configuration to the bundled script path listed in the handbook.",
            "template",
        ),
        "name_generator_unavailable": _make_guidance(
            "NameGenerator singleton or script is unavailable.",
            "Enable the autoloads noted in the launch checklist or restore the default script path.",
            "template",
        ),
        "invalid_steps_type": _make_guidance(
            "Hybrid strategy expects 'steps' to be an Array of dictionaries.",
            "Collect step definitions through the Hybrid panel so the payload structure matches the handbook.",
            "hybrid",
        ),
        "empty_steps": _make_guidance(
            "Hybrid strategy requires at least one configured step.",
            "Add a step that points to a generator or reuse the starter pipelines documented in the handbook.",
            "hybrid",
        ),
        "invalid_step_entry": _make_guidance(
            "Each hybrid step must be a Dictionary entry.",
            "Recreate the step via the GUI to avoid mixing scalar values with configuration dictionaries.",
            "hybrid",
        ),
        "invalid_step_config": _make_guidance(
            "Hybrid step 'config' payload must be a Dictionary.",
            "Open the child panel referenced in the handbook to capture a fresh configuration block.",
            "hybrid",
        ),
        "missing_step_strategy": _make_guidance(
            "Hybrid step is missing its 'strategy' identifier.",
            "Select a generator for every step so the middleware knows which strategy to invoke.",
            "hybrid",
        ),
        "hybrid_step_error": _make_guidance(
            "A nested hybrid step reported its own error.",
            "Inspect the step details and open the referenced panel for targeted troubleshooting.",
            "hybrid",
        ),
        "invalid_markov_model_path": _make_guidance(
            "'markov_model_path' must point to a MarkovModelResource.",
            "Select a model from the Dataset Health inventory before requesting a preview.",
            "markov",
        ),
        "missing_markov_model_path": _make_guidance(
            "Configuration omitted the Markov model path.",
            "Fill in the model path or pick a dataset using the Markov panel workflow.",
            "markov",
        ),
        "invalid_model_states": _make_guidance(
            "Markov model state table is malformed.",
            "Re-export the dataset using the builder to refresh state counts.",
            "markov",
        ),
        "invalid_model_start_tokens": _make_guidance(
            "Start token array contains invalid data.",
            "Verify the start token definitions following the Markov checklist.",
            "markov",
        ),
        "invalid_model_end_tokens": _make_guidance(
            "End token array contains invalid data.",
            "Review the termination tokens described in the handbook and update the resource.",
            "markov",
        ),
        "invalid_transitions_type": _make_guidance(
            "Transition table must be a Dictionary keyed by token.",
            "Regenerate the model to ensure transitions use the documented schema.",
            "markov",
        ),
        "empty_transition_block": _make_guidance(
            "Transition table contains an empty block.",
            "Populate every transition bucket or remove unused tokens before exporting.",
            "markov",
        ),
        "invalid_transition_block": _make_guidance(
            "Transition block does not match the expected array layout.",
            "Restore the weight/value pairs illustrated in the handbook transition examples.",
            "markov",
        ),
        "invalid_transition_entry_type": _make_guidance(
            "Transition entries must be Dictionaries describing token/weight pairs.",
            "Rebuild the transitions using the Markov editor workflow.",
            "markov",
        ),
        "invalid_transition_token_type": _make_guidance(
            "Transition entry token must be a String.",
            "Review the dataset export script and ensure tokens are serialised as text.",
            "markov",
        ),
        "invalid_transition_weight_type": _make_guidance(
            "Transition weight must be numeric.",
            "Normalise weight values to floats or integers before exporting the model.",
            "markov",
        ),
        "invalid_transition_weight_value": _make_guidance(
            "Transition weight must be greater than zero.",
            "Remove negative or zero weights so sampling behaves predictably.",
            "markov",
        ),
        "non_positive_weight_sum": _make_guidance(
            "Transition weights sum to zero or less.",
            "Rebalance the weights so they sum to a positive value as shown in the handbook.",
            "markov",
        ),
        "missing_transition_token": _make_guidance(
            "A transition entry is missing its token value.",
            "Add the token string or delete the incomplete entry before exporting.",
            "markov",
        ),
        "missing_transition_for_token": _make_guidance(
            "Model lacks a transition table for one of the referenced tokens.",
            "Regenerate the dataset to include transitions for every token referenced in the state table.",
            "markov",
        ),
        "unknown_token_reference": _make_guidance(
            "Transition references a token that is not defined in the model.",
            "Cross-check the token inventory and remove stale references.",
            "markov",
        ),
        "invalid_token_temperature_type": _make_guidance(
            "Temperature overrides must be numeric.",
            "Set token temperatures to floats as demonstrated in the handbook examples.",
            "markov",
        ),
        "invalid_token_temperature_value": _make_guidance(
            "Token temperature must be greater than zero.",
            "Use positive values when adjusting token temperature overrides.",
            "markov",
        ),
        "invalid_transition_temperature_type": _make_guidance(
            "Transition temperature overrides must be numeric.",
            "Ensure transition overrides mirror the numeric structure from the handbook.",
            "markov",
        ),
        "invalid_transition_temperature_value": _make_guidance(
            "Transition temperature must be greater than zero.",
            "Audit override values and keep them positive as shown in the troubleshooting guide.",
            "markov",
        ),
        "invalid_default_temperature": _make_guidance(
            "Default temperature must be numeric and above zero.",
            "Update the config to use the safe defaults captured in the handbook.",
            "markov",
        ),
        "invalid_max_length_type": _make_guidance(
            "max_length must be an integer.",
            "Provide numeric values when clamping generated token counts.",
            "markov",
        ),
        "invalid_max_length_value": _make_guidance(
            "max_length must be greater than zero.",
            "Use the minimum thresholds suggested in the handbook before sampling.",
            "markov",
        ),
        "max_length_exceeded": _make_guidance(
            "Generation stopped after exceeding the configured max_length.",
            "Increase max_length or relax temperature constraints per the troubleshooting table.",
            "markov",
        ),
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
    var merged := _duplicate_guidance_map(_BASE_ERROR_GUIDE)
    var key := _normalize_strategy_id(strategy_id)
    if key == "" or not _metadata_cache.has(key):
        return merged
    var entry: Dictionary = _metadata_cache[key]
    var hints: Dictionary = entry.get("error_hints", {})
    for hint_code in hints.keys():
        var override := hints[hint_code]
        var base_entry: Dictionary = {}
        if merged.has(hint_code) and merged[hint_code] is Dictionary:
            base_entry = _duplicate_dictionary(merged[hint_code])
        if override is Dictionary:
            var override_dict: Dictionary = _duplicate_dictionary(override)
            for override_key in override_dict.keys():
                base_entry[override_key] = override_dict[override_key]
            merged[hint_code] = base_entry
        else:
            base_entry["message"] = String(override)
            if not merged.has(hint_code):
                merged[hint_code] = base_entry
            else:
                merged[hint_code] = base_entry
    return merged

func get_generator_error_guidance(strategy_id: String, code: String) -> Dictionary:
    if code == "":
        return {}
    var hints := get_generator_error_hints(strategy_id)
    var entry_variant: Variant = hints.get(code, {})
    if entry_variant is Dictionary:
        return _duplicate_dictionary(entry_variant)
    elif typeof(entry_variant) == TYPE_STRING and String(entry_variant) != "":
        return {"message": String(entry_variant)}
    return {}

func get_generator_error_hint(strategy_id: String, code: String) -> String:
    var guidance := get_generator_error_guidance(strategy_id, code)
    if guidance.is_empty():
        return ""
    var lines: Array[String] = []
    var message := String(guidance.get("message", ""))
    if message != "":
        lines.append(message)
    var remediation := String(guidance.get("remediation", ""))
    if remediation != "":
        lines.append("Try: %s" % remediation)
    var handbook_label := String(guidance.get("handbook_label", ""))
    if handbook_label != "":
        var anchor := String(guidance.get("handbook_anchor", ""))
        if anchor != "":
            lines.append("Handbook: %s (#%s)" % [handbook_label, anchor])
        else:
            lines.append("Handbook: %s" % handbook_label)
    return "\n".join(lines)

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
        var required_hint := _duplicate_dictionary(_BASE_ERROR_GUIDE.get("missing_required_keys", {}))
        required_hint["message"] = "Include required keys: %s." % ", ".join(required_keys)
        hints["missing_required_keys"] = required_hint
    else:
        hints["missing_required_keys"] = _duplicate_dictionary(_BASE_ERROR_GUIDE.get("missing_required_keys", {}))

    if optional_key_types.size() > 0:
        var segments: Array[String] = []
        var keys := optional_key_types.keys()
        keys.sort()
        for key in keys:
            var expected_type: int = int(optional_key_types[key])
            segments.append("%s (%s)" % [String(key), type_string(expected_type)])
        var optional_hint := _duplicate_dictionary(_BASE_ERROR_GUIDE.get("invalid_key_type", {}))
        optional_hint["message"] = "Optional keys must use expected types such as %s." % ", ".join(segments)
        hints["invalid_key_type"] = optional_hint
    else:
        hints["invalid_key_type"] = _duplicate_dictionary(_BASE_ERROR_GUIDE.get("invalid_key_type", {}))

    return hints

func _duplicate_guidance_map(source: Dictionary) -> Dictionary:
    var clone: Dictionary = {}
    for key in source.keys():
        var entry := source[key]
        if entry is Dictionary:
            clone[key] = _duplicate_dictionary(entry)
        else:
            clone[key] = entry
    return clone

func _duplicate_dictionary(value: Dictionary) -> Dictionary:
    var clone: Dictionary = {}
    for key in value.keys():
        clone[key] = value[key]
    return clone
