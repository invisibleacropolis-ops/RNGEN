extends VBoxContainer

## Platform GUI panel that configures the MarkovChainStrategy.
##
## The widget mirrors other strategy panels by discovering project assets,
## summarising configuration metadata, and exposing seeded previews through the
## RNGProcessor controller. It additionally analyses Markov models to surface
## transition health indicators so artists can assess corpus quality without
## leaving the editor.

@export var controller_path: NodePath
@export var metadata_service_path: NodePath

const MarkovModelResource := preload("res://name_generator/resources/MarkovModelResource.gd")

@onready var _resource_list: ItemList = %ResourceList
@onready var _resource_summary: RichTextLabel = %ResourceSummary
@onready var _health_label: RichTextLabel = %HealthLabel
@onready var _max_length_spin: SpinBox = %MaxLengthSpin
@onready var _seed_edit: LineEdit = %SeedInput
@onready var _preview_button: Button = %PreviewButton
@onready var _preview_label: RichTextLabel = %PreviewOutput
@onready var _validation_label: Label = %ValidationLabel
@onready var _validation_details: RichTextLabel = %ValidationDetails
@onready var _metadata_summary: Label = %MetadataSummary
@onready var _notes_label: Label = %NotesLabel

var _controller_override: Object = null
var _cached_controller: Object = null
var _metadata_service_override: Object = null
var _cached_metadata_service: Object = null
var _resource_catalog_override: Array = []
var _resource_cache: Array = []

const _SUCCESS_COLOUR := Color(0.176, 0.647, 0.258)
const _WARNING_COLOUR := Color(0.831, 0.541, 0.0)
const _ERROR_COLOUR := Color(0.82, 0.18, 0.2)

func _ready() -> void:
    _preview_button.pressed.connect(_on_preview_button_pressed)
    %RefreshButton.pressed.connect(_on_refresh_pressed)
    _resource_list.item_selected.connect(_on_resource_selected)
    _seed_edit.text_submitted.connect(_on_seed_submitted)
    _refresh_metadata()
    _refresh_resource_catalog()
    _update_preview_state(null)

func set_controller_override(controller: Object) -> void:
    _controller_override = controller
    _cached_controller = null

func set_metadata_service_override(service: Object) -> void:
    _metadata_service_override = service
    _cached_metadata_service = null

func set_resource_catalog_override(entries: Array) -> void:
    _resource_catalog_override = entries.duplicate(true)
    _refresh_resource_catalog()

func refresh() -> void:
    _refresh_metadata()
    _refresh_resource_catalog()

func get_selected_resource_path() -> String:
    return _get_selected_resource_path()

func build_config_payload() -> Dictionary:
    var config: Dictionary = {
        "strategy": "markov",
    }
    var path := _get_selected_resource_path()
    if path != "":
        config["markov_model_path"] = path
    var max_length := int(_max_length_spin.value)
    if max_length > 0:
        config["max_length"] = max_length
    var seed_value := _seed_edit.text.strip_edges()
    if seed_value != "":
        config["seed"] = seed_value
    return config

func _on_refresh_pressed() -> void:
    refresh()

func _on_resource_selected(_index: int) -> void:
    _update_selected_resource_summary()

func _on_preview_button_pressed() -> void:
    var controller := _get_controller()
    if controller == null:
        _update_preview_state({
            "status": "error",
            "message": "RNGProcessor controller unavailable.",
        })
        return

    var config := build_config_payload()
    var model_path := String(config.get("markov_model_path", ""))
    if model_path == "":
        _update_preview_state({
            "status": "error",
            "message": "Select a MarkovModelResource to preview output.",
        })
        return

    var response: Variant = controller.call("generate", config)
    if response is Dictionary and response.has("code"):
        var error_dict: Dictionary = response
        _update_preview_state({
            "status": "error",
            "message": String(error_dict.get("message", "Generation failed.")),
            "details": error_dict.get("details", {}),
        })
        return

    _update_preview_state({
        "status": "success",
        "message": String(response),
    })

func _on_seed_submitted(text: String) -> void:
    _seed_edit.text = text
    _on_preview_button_pressed()

func _refresh_metadata() -> void:
    var service := _get_metadata_service()
    if service == null:
        _metadata_summary.text = "Markov strategy metadata unavailable."
        _notes_label.text = ""
        return

    var required_variant := []
    if service.has_method("get_required_keys"):
        required_variant = service.call("get_required_keys", "markov")
    var optional: Dictionary = {}
    if service.has_method("get_optional_key_types"):
        optional = service.call("get_optional_key_types", "markov")
    var notes_variant := []
    if service.has_method("get_default_notes"):
        notes_variant = service.call("get_default_notes", "markov")

    var required_list: Array[String] = []
    if required_variant is PackedStringArray:
        required_list.assign(required_variant)
    elif required_variant is Array:
        for value in required_variant:
            required_list.append(String(value))

    var summary_parts := []
    if not required_list.is_empty():
        summary_parts.append("Requires: %s" % ", ".join(required_list))
    if optional is Dictionary and not optional.is_empty():
        var optional_strings: Array[String] = []
        for key in optional.keys():
            var variant_type := int(optional[key])
            optional_strings.append("%s (%s)" % [key, Variant.get_type_name(variant_type)])
        optional_strings.sort()
        summary_parts.append("Optional: %s" % ", ".join(optional_strings))
    _metadata_summary.text = " | ".join(summary_parts)

    var notes: Array[String] = []
    if notes_variant is PackedStringArray:
        notes.assign(notes_variant)
    elif notes_variant is Array:
        for value in notes_variant:
            notes.append(String(value))

    if not notes.is_empty():
        _notes_label.text = "\n".join(notes)
    else:
        _notes_label.text = ""

func _refresh_resource_catalog() -> void:
    _resource_list.clear()
    _resource_cache.clear()

    var descriptors: Array = []
    if not _resource_catalog_override.is_empty():
        descriptors = _resource_catalog_override.duplicate(true)
    else:
        descriptors = _discover_markov_resources()

    descriptors.sort_custom(func(a, b):
        var left_name := String(a.get("display_name", a.get("path", "")))
        var right_name := String(b.get("display_name", b.get("path", "")))
        return left_name.nocasecmp_to(right_name) < 0
    )

    for descriptor in descriptors:
        if not (descriptor is Dictionary):
            continue
        var path := String(descriptor.get("path", ""))
        if path == "":
            continue
        var display_name := String(descriptor.get("display_name", path))
        var metadata := {
            "path": path,
            "display_name": display_name,
            "locale": String(descriptor.get("locale", "")),
            "domain": String(descriptor.get("domain", "")),
        }
        var detail_parts: Array[String] = []
        if metadata["locale"] != "":
            detail_parts.append(metadata["locale"])
        if metadata["domain"] != "":
            detail_parts.append(metadata["domain"])
        var detail_suffix := detail_parts.join(" · ")
        var line := display_name
        if detail_suffix != "":
            line += " — %s" % detail_suffix
        var item_index := _resource_list.add_item(line)
        _resource_list.set_item_metadata(item_index, metadata)
        _resource_list.set_item_tooltip(item_index, "%s\nPath: %s" % [line, path])
        _resource_cache.append(metadata)

    if _resource_list.item_count == 0:
        _resource_list.add_item("No MarkovModelResource assets found.")
        _resource_list.set_item_disabled(0, true)

    _resource_summary.bbcode_text = "Select a Markov model to review its states and transitions."
    _health_label.bbcode_text = ""

func _discover_markov_resources() -> Array:
    var results: Array = []
    var stack: Array[String] = ["res://data"]
    while not stack.is_empty():
        var path := stack.pop_back()
        var dir := DirAccess.open(path)
        if dir == null:
            continue
        dir.list_dir_begin()
        var entry := dir.get_next()
        while entry != "":
            if dir.current_is_dir():
                if entry.begins_with("."):
                    entry = dir.get_next()
                    continue
                stack.append(path.path_join(entry))
            else:
                if not (entry.ends_with(".tres") or entry.ends_with(".res")):
                    entry = dir.get_next()
                    continue
                var resource_path := path.path_join(entry)
                if not ResourceLoader.exists(resource_path):
                    entry = dir.get_next()
                    continue
                var resource: Resource = ResourceLoader.load(resource_path)
                if resource == null or not (resource is MarkovModelResource):
                    entry = dir.get_next()
                    continue
                var model: MarkovModelResource = resource
                results.append({
                    "path": resource_path,
                    "display_name": _derive_display_name(resource_path),
                    "locale": model.locale,
                    "domain": model.domain,
                })
            entry = dir.get_next()
        dir.list_dir_end()
    return results

func _derive_display_name(path: String) -> String:
    var segments := path.split("/")
    if segments.is_empty():
        return path
    var filename := segments.back()
    var trimmed := filename.replace(".tres", "").replace(".res", "")
    return trimmed.capitalize()

func _update_selected_resource_summary() -> void:
    var path := _get_selected_resource_path()
    if path == "":
        _resource_summary.bbcode_text = "Select a Markov model to review its states and transitions."
        _health_label.bbcode_text = ""
        return

    if not ResourceLoader.exists(path):
        _resource_summary.bbcode_text = "Unable to load resource at %s" % path
        _health_label.bbcode_text = ""
        return

    var resource: Resource = ResourceLoader.load(path)
    if resource == null or not (resource is MarkovModelResource):
        _resource_summary.bbcode_text = "Resource at %s is not a MarkovModelResource." % path
        _health_label.bbcode_text = ""
        return

    var model: MarkovModelResource = resource
    var analysis := _analyse_model(model)
    _resource_summary.bbcode_text = _format_model_summary(model, analysis)
    _health_label.bbcode_text = _format_health_summary(analysis)

func _analyse_model(model: MarkovModelResource) -> Dictionary:
    var states := PackedStringArray()
    states.assign(model.states)
    var end_tokens := PackedStringArray()
    end_tokens.assign(model.end_tokens)
    var start_tokens := PackedStringArray()
    var invalid_references := PackedStringArray()
    var invalid_reference_lookup := {}
    var transitions_total := 0
    var states_with_arcs := PackedStringArray()
    var missing_transitions := PackedStringArray()
    var weight_type_issues: PackedStringArray = PackedStringArray()
    var weight_value_issues: PackedStringArray = PackedStringArray()
    var temperature_issues: PackedStringArray = PackedStringArray()
    var adjacency: Dictionary = {}
    var direct_terminators := PackedStringArray()

    for entry in model.start_tokens:
        if not (entry is Dictionary):
            continue
        var token_value := String(entry.get("token", ""))
        if token_value == "":
            continue
        if not start_tokens.has(token_value):
            start_tokens.append(token_value)
        if not states.has(token_value) and not end_tokens.has(token_value):
            if not invalid_reference_lookup.has(token_value):
                invalid_reference_lookup[token_value] = true
                invalid_references.append(token_value)
        var weight_value: Variant = entry.get("weight", 1.0)
        if typeof(weight_value) != TYPE_FLOAT and typeof(weight_value) != TYPE_INT:
            weight_type_issues.append("start → %s" % token_value)
        elif float(weight_value) <= 0.0:
            weight_value_issues.append("start → %s" % token_value)
        if entry.has("temperature"):
            var temperature_value: Variant = entry.get("temperature")
            if typeof(temperature_value) != TYPE_FLOAT and typeof(temperature_value) != TYPE_INT:
                temperature_issues.append("start → %s" % token_value)
            elif float(temperature_value) <= 0.0:
                temperature_issues.append("start → %s" % token_value)

    for key in model.transitions.keys():
        var state_id := String(key)
        var block := model.get_transition_block(state_id)
        if block.is_empty():
            if states.has(state_id):
                if not missing_transitions.has(state_id):
                    missing_transitions.append(state_id)
            else:
                if not invalid_reference_lookup.has(state_id):
                    invalid_reference_lookup[state_id] = true
                    invalid_references.append(state_id)
            continue
        if not adjacency.has(state_id):
            adjacency[state_id] = []
        if states.has(state_id) and not states_with_arcs.has(state_id):
            states_with_arcs.append(state_id)
        for option in block:
            if not (option is Dictionary):
                continue
            var token_value := String(option.get("token", ""))
            if token_value == "":
                if not invalid_reference_lookup.has(token_value):
                    invalid_reference_lookup[token_value] = true
                    invalid_references.append(token_value)
                continue
            transitions_total += 1
            var context := "%s → %s" % [state_id, token_value]
            var weight_value: Variant = option.get("weight", 1.0)
            if typeof(weight_value) != TYPE_FLOAT and typeof(weight_value) != TYPE_INT:
                weight_type_issues.append(context)
            elif float(weight_value) <= 0.0:
                weight_value_issues.append(context)
            if option.has("temperature"):
                var temperature_value: Variant = option.get("temperature")
                if typeof(temperature_value) != TYPE_FLOAT and typeof(temperature_value) != TYPE_INT:
                    temperature_issues.append(context)
                elif float(temperature_value) <= 0.0:
                    temperature_issues.append(context)
            var neighbours: Array = adjacency[state_id]
            neighbours.append(token_value)
            adjacency[state_id] = neighbours
            if end_tokens.has(token_value):
                if not direct_terminators.has(state_id):
                    direct_terminators.append(state_id)
            elif not states.has(token_value):
                if not invalid_reference_lookup.has(token_value):
                    invalid_reference_lookup[token_value] = true
                    invalid_references.append(token_value)

    for state in states:
        if not adjacency.has(state):
            adjacency[state] = []
        if not states_with_arcs.has(state):
            if not missing_transitions.has(state):
                missing_transitions.append(state)

    var reachable_info := _calculate_start_reachability(start_tokens, adjacency, end_tokens)

    var override_values: Array[float] = []
    for token in model.token_temperatures.keys():
        var override_value: Variant = model.token_temperatures[token]
        var context := "override %s" % String(token)
        if typeof(override_value) == TYPE_FLOAT or typeof(override_value) == TYPE_INT:
            var numeric := float(override_value)
            if numeric > 0.0:
                override_values.append(numeric)
            else:
                temperature_issues.append(context)
        else:
            temperature_issues.append(context)

    override_values.sort()

    return {
        "state_count": states.size(),
        "start_tokens": start_tokens,
        "start_token_total": start_tokens.size(),
        "end_tokens": end_tokens,
        "transitions_total": transitions_total,
        "states_with_transitions": states_with_arcs.size(),
        "missing_transitions": missing_transitions,
        "invalid_references": invalid_references,
        "weight_type_issues": weight_type_issues,
        "weight_value_issues": weight_value_issues,
        "temperature_issues": temperature_issues,
        "direct_terminators": direct_terminators,
        "reachable_start_tokens": int(reachable_info.get("reachable", 0)),
        "unreachable_start_tokens": reachable_info.get("unreachable", PackedStringArray()),
        "temperature_overrides": override_values,
        "default_temperature": model.default_temperature,
    }

func _calculate_start_reachability(start_tokens: PackedStringArray, adjacency: Dictionary, end_tokens: PackedStringArray) -> Dictionary:
    var reachable := 0
    var unreachable := PackedStringArray()
    for token in start_tokens:
        if token == "":
            continue
        if _can_reach_end(token, adjacency, end_tokens):
            reachable += 1
        else:
            unreachable.append(token)
    return {
        "reachable": reachable,
        "unreachable": unreachable,
    }

func _can_reach_end(token: String, adjacency: Dictionary, end_tokens: PackedStringArray) -> bool:
    if token == "":
        return false
    if end_tokens.has(token):
        return true
    var visited := {}
    var stack: Array[String] = [token]
    while not stack.is_empty():
        var current := stack.pop_back()
        if end_tokens.has(current):
            return true
        if visited.has(current):
            continue
        visited[current] = true
        if not adjacency.has(current):
            continue
        var neighbours: Variant = adjacency[current]
        if neighbours is Array:
            for neighbour in neighbours:
                var next_token := String(neighbour)
                if next_token == "":
                    continue
                if end_tokens.has(next_token):
                    return true
                if not visited.has(next_token):
                    stack.append(next_token)
    return false

func _format_model_summary(model: MarkovModelResource, analysis: Dictionary) -> String:
    var lines: Array[String] = []
    lines.append("[b]States[/b]: %d" % int(analysis.get("state_count", 0)))
    var start_tokens := _to_packed_string_array(analysis.get("start_tokens", PackedStringArray()))
    if start_tokens.size() > 0:
        lines.append("[b]Start tokens[/b]: %d (%s)" % [start_tokens.size(), _format_token_sample(start_tokens)])
    else:
        lines.append("[b]Start tokens[/b]: 0")
    var end_tokens := _to_packed_string_array(analysis.get("end_tokens", PackedStringArray()))
    if end_tokens.size() > 0:
        lines.append("[b]End tokens[/b]: %d (%s)" % [end_tokens.size(), _format_token_sample(end_tokens)])
    else:
        lines.append("[b]End tokens[/b]: 0")
    var overrides := _to_float_array(analysis.get("temperature_overrides", []))
    var default_temperature := float(analysis.get("default_temperature", model.default_temperature))
    if overrides.size() > 0:
        var min_override := overrides[0]
        var max_override := overrides[overrides.size() - 1]
        lines.append("[b]Temperature overrides[/b]: %d (%.2f–%.2f), default %.2f" % [overrides.size(), min_override, max_override, default_temperature])
    else:
        lines.append("[b]Temperature overrides[/b]: 0 (default %.2f)" % default_temperature)
    return "\n".join(lines)

func _format_health_summary(analysis: Dictionary) -> String:
    var lines: Array[String] = []
    var state_count := int(analysis.get("state_count", 0))
    var states_with_transitions := int(analysis.get("states_with_transitions", 0))
    var transitions_total := int(analysis.get("transitions_total", 0))
    var missing_transitions := _to_packed_string_array(analysis.get("missing_transitions", PackedStringArray()))
    if state_count > 0:
        if missing_transitions.is_empty() and states_with_transitions >= state_count:
            lines.append(_wrap_health_message("✔ All %d states define transitions (%d options)." % [state_count, transitions_total], _SUCCESS_COLOUR))
        else:
            lines.append(_wrap_health_message("⚠ %d/%d states define transitions (%d options)." % [states_with_transitions, state_count, transitions_total], _WARNING_COLOUR))
            if not missing_transitions.is_empty():
                lines.append(_wrap_health_message("• Missing transitions for: %s" % _format_token_sample(missing_transitions), _WARNING_COLOUR))

    var start_total := int(analysis.get("start_token_total", 0))
    var reachable := int(analysis.get("reachable_start_tokens", 0))
    var unreachable := _to_packed_string_array(analysis.get("unreachable_start_tokens", PackedStringArray()))
    if start_total > 0:
        if reachable >= start_total and unreachable.is_empty():
            lines.append(_wrap_health_message("✔ All %d start tokens can reach an end token." % start_total, _SUCCESS_COLOUR))
        else:
            lines.append(_wrap_health_message("⚠ Only %d/%d start tokens reach an end token." % [reachable, start_total], _WARNING_COLOUR))
            if not unreachable.is_empty():
                lines.append(_wrap_health_message("• Unreachable: %s" % _format_token_sample(unreachable), _WARNING_COLOUR))

    var invalid_references := _to_packed_string_array(analysis.get("invalid_references", PackedStringArray()))
    if not invalid_references.is_empty():
        lines.append(_wrap_health_message("⚠ Unknown token references: %s" % _format_token_sample(invalid_references), _ERROR_COLOUR))

    var weight_type_issues := _to_packed_string_array(analysis.get("weight_type_issues", PackedStringArray()))
    if not weight_type_issues.is_empty():
        lines.append(_wrap_health_message("⚠ Non-numeric weights: %s" % _format_token_sample(weight_type_issues), _ERROR_COLOUR))

    var weight_value_issues := _to_packed_string_array(analysis.get("weight_value_issues", PackedStringArray()))
    if not weight_value_issues.is_empty():
        lines.append(_wrap_health_message("⚠ Non-positive weights: %s" % _format_token_sample(weight_value_issues), _ERROR_COLOUR))

    var temperature_issues := _to_packed_string_array(analysis.get("temperature_issues", PackedStringArray()))
    if not temperature_issues.is_empty():
        lines.append(_wrap_health_message("⚠ Invalid temperature overrides: %s" % _format_token_sample(temperature_issues), _ERROR_COLOUR))

    var direct_terminators := _to_packed_string_array(analysis.get("direct_terminators", PackedStringArray()))
    if direct_terminators.size() > 0:
        lines.append(_wrap_health_message("• %d states emit end tokens directly (%s)." % [direct_terminators.size(), _format_token_sample(direct_terminators)], _SUCCESS_COLOUR))

    if lines.is_empty():
        return ""
    return "\n".join(lines)

func _wrap_health_message(message: String, colour: Color) -> String:
    return "[color=#%s]%s[/color]" % [colour.to_html(false), message]

func _format_token_sample(tokens: PackedStringArray, limit: int = 4) -> String:
    if tokens.size() == 0:
        return "—"
    var sample: Array[String] = []
    for index in range(min(tokens.size(), limit)):
        var token := String(tokens[index])
        if token == "":
            token = "(blank)"
        sample.append(token)
    if tokens.size() > limit:
        sample.append("…")
    return ", ".join(sample)

func _to_packed_string_array(value: Variant) -> PackedStringArray:
    var result := PackedStringArray()
    if value is PackedStringArray:
        result.assign(value)
    elif value is Array:
        for entry in value:
            result.append(String(entry))
    elif value is String:
        result.append(value)
    return result

func _to_float_array(value: Variant) -> Array[float]:
    var result: Array[float] = []
    if value is Array:
        for entry in value:
            result.append(float(entry))
    elif value is PackedFloat32Array:
        for entry in value:
            result.append(float(entry))
    return result

func _update_preview_state(payload: Dictionary) -> void:
    _preview_label.visible = false
    _preview_label.text = ""
    _validation_label.visible = false
    _validation_label.text = ""
    _validation_details.visible = false
    _validation_details.bbcode_text = ""
    if payload == null:
        return
    var status := String(payload.get("status", ""))
    var message := String(payload.get("message", ""))
    if status == "success":
        _preview_label.visible = true
        _preview_label.text = "[b]Preview:[/b]\n%s" % message
    else:
        _validation_label.visible = true
        _validation_label.text = message
        var details_text := _format_error_details(payload.get("details", {}))
        if details_text != "":
            _validation_details.visible = true
            _validation_details.bbcode_text = details_text

func _format_error_details(details: Variant) -> String:
    if details is Dictionary and not (details as Dictionary).is_empty():
        var dictionary: Dictionary = details
        var keys := dictionary.keys()
        keys.sort()
        var lines: Array[String] = []
        for key in keys:
            var value := dictionary[key]
            lines.append("- [b]%s[/b]: %s" % [String(key), _stringify_detail_value(value)])
        return "[b]Details:[/b]\n%s" % "\n".join(lines)
    if details is Array and (details as Array).size() > 0:
        var array: Array = details
        var lines: Array[String] = []
        for item in array:
            lines.append("- %s" % _stringify_detail_value(item))
        return "[b]Details:[/b]\n%s" % "\n".join(lines)
    return ""

func _stringify_detail_value(value: Variant) -> String:
    if value is PackedStringArray:
        var packed: PackedStringArray = value
        var items: Array[String] = []
        for entry in packed:
            items.append(String(entry))
        return ", ".join(items)
    if value is Array or value is Dictionary:
        return JSON.stringify(value)
    return String(value)

func _get_selected_resource_path() -> String:
    var selected := _resource_list.get_selected_items()
    if selected.is_empty():
        return ""
    var index := selected[0]
    if index < 0 or index >= _resource_list.item_count:
        return ""
    var metadata: Variant = _resource_list.get_item_metadata(index)
    if metadata is Dictionary:
        return String((metadata as Dictionary).get("path", ""))
    return ""

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

func _get_metadata_service() -> Object:
    if _metadata_service_override != null and _is_object_valid(_metadata_service_override):
        return _metadata_service_override
    if _cached_metadata_service != null and _is_object_valid(_cached_metadata_service):
        return _cached_metadata_service
    if metadata_service_path != NodePath("") and has_node(metadata_service_path):
        var node := get_node(metadata_service_path)
        if node != null:
            _cached_metadata_service = node
            return _cached_metadata_service
    if Engine.has_singleton("StrategyMetadataService"):
        var singleton := Engine.get_singleton("StrategyMetadataService")
        if _is_object_valid(singleton):
            _cached_metadata_service = singleton
            return _cached_metadata_service
    return null

func _is_object_valid(candidate: Object) -> bool:
    if candidate == null:
        return false
    if candidate is Node:
        return is_instance_valid(candidate)
    return true
