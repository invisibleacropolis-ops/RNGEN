extends VBoxContainer

## Platform GUI panel that configures TemplateStrategy instances.
##
## The panel parses author-provided template strings, visualises the resulting
## token tree, and surfaces validation hints sourced from the middleware's
## metadata cache. Configuration controls mirror TemplateStrategy's schema,
## including support for nested sub-generator dictionaries and configurable
## recursion limits. The widget mirrors the behaviour exposed by the other
## strategy panels so it can be dropped into existing editor hierarchies
## without additional wiring.

@export var controller_path: NodePath
@export var metadata_service_path: NodePath

signal configuration_changed

const TEMPLATE_STRATEGY_ID := "template"
const TOKEN_PATTERN := "\\[(?<token>[^\\[\\]]+)\\]"
const DEFAULT_MAX_DEPTH := 8
const _ERROR_TINT := Color(1.0, 0.85, 0.85, 1.0)

@onready var _metadata_summary: Label = %MetadataSummary
@onready var _notes_label: Label = %NotesLabel
@onready var _template_input: TextEdit = %TemplateInput
@onready var _max_depth_spin: SpinBox = %MaxDepthSpin
@onready var _seed_edit: LineEdit = %SeedInput
@onready var _seed_helper: Label = %SeedHelper
@onready var _sub_generators_edit: TextEdit = %SubGeneratorInput
@onready var _token_tree: Tree = %TokenTree
@onready var _validation_label: Label = %ValidationLabel
@onready var _fix_it_label: Label = %FixItLabel
@onready var _preview_button: Button = %PreviewButton
@onready var _preview_label: RichTextLabel = %PreviewOutput

var _controller_override: Object = null
var _cached_controller: Object = null
var _metadata_service_override: Object = null
var _cached_metadata_service: Object = null
var _control_default_modulates: Dictionary = {}
var _token_regex: RegEx = null

func _ready() -> void:
    _preview_button.pressed.connect(_on_preview_button_pressed)
    %RefreshButton.pressed.connect(_on_refresh_pressed)
    _template_input.text_changed.connect(_on_template_changed)
    _sub_generators_edit.text_changed.connect(_on_sub_generators_changed)
    _max_depth_spin.value_changed.connect(_on_max_depth_changed)
    _seed_edit.text_changed.connect(_on_seed_changed)
    _seed_edit.text_submitted.connect(_on_seed_submitted)
    _token_tree.set_column_titles_visible(true)
    _token_tree.set_column_title(0, "Node")
    _token_tree.set_column_title(1, "Depth")
    _token_tree.set_column_title(2, "Strategy")
    _token_tree.set_column_title(3, "Seed")
    _track_default_modulate(_template_input)
    _track_default_modulate(_sub_generators_edit)
    _track_default_modulate(_max_depth_spin)
    _track_default_modulate(_token_tree)
    _refresh_metadata()
    _update_seed_helper()
    _rebuild_configuration_views()

func apply_config_payload(config: Dictionary) -> void:
    var template_string := String(config.get("template_string", ""))
    if _template_input.text != template_string:
        _template_input.text = template_string
    var max_depth := int(config.get("max_depth", DEFAULT_MAX_DEPTH))
    if int(_max_depth_spin.value) != max_depth:
        _max_depth_spin.value = max_depth
    var seed_value := String(config.get("seed", ""))
    if _seed_edit.text != seed_value:
        _seed_edit.text = seed_value
    var sub_generators := config.get("sub_generators", {})
    if typeof(sub_generators) == TYPE_DICTIONARY:
        var json := JSON.stringify(sub_generators, "  ")
        if _sub_generators_edit.text != json:
            _sub_generators_edit.text = json
    else:
        if _sub_generators_edit.text != "":
            _sub_generators_edit.text = ""
    _rebuild_configuration_views()
    _update_seed_helper()
    _notify_configuration_changed()

func evaluate_configuration(seed_override: String = "") -> Dictionary:
    return _evaluate_configuration(seed_override)

func set_controller_override(controller: Object) -> void:
    _controller_override = controller
    _cached_controller = null
    _update_seed_helper()

func set_metadata_service_override(service: Object) -> void:
    _metadata_service_override = service
    _cached_metadata_service = null
    _refresh_metadata()
    _rebuild_configuration_views()

func refresh() -> void:
    _refresh_metadata()
    _rebuild_configuration_views()
    _update_seed_helper()

func build_config_payload() -> Dictionary:
    var config: Dictionary = {
        "strategy": TEMPLATE_STRATEGY_ID,
        "template_string": _template_input.text,
    }
    var max_depth := int(_max_depth_spin.value)
    if max_depth != DEFAULT_MAX_DEPTH:
        config["max_depth"] = max_depth
    var seed_value := _seed_edit.text.strip_edges()
    if seed_value != "":
        config["seed"] = seed_value
    var sub_generators := _parse_sub_generator_dictionary()
    if not sub_generators.is_empty():
        config["sub_generators"] = sub_generators
    return config

func get_child_generator_definitions() -> Dictionary:
    return _parse_sub_generator_dictionary()

func _on_refresh_pressed() -> void:
    refresh()

func _on_template_changed() -> void:
    _rebuild_configuration_views()
    _notify_configuration_changed()

func _on_sub_generators_changed() -> void:
    _rebuild_configuration_views()
    _notify_configuration_changed()

func _on_max_depth_changed(_value: float) -> void:
    _rebuild_configuration_views()
    _notify_configuration_changed()

func _on_seed_changed(_text: String) -> void:
    _rebuild_configuration_views()
    _update_seed_helper()
    _notify_configuration_changed()

func _on_preview_button_pressed() -> void:
    var controller := _get_controller()
    if controller == null:
        _update_preview_state({
            "status": "error",
            "message": "RNGProcessor controller unavailable.",
        })
        return

    var evaluation := _evaluate_configuration()
    _render_token_tree(evaluation["structure"])
    _apply_validation_feedback(evaluation["errors"])
    if not evaluation["errors"].is_empty():
        _update_preview_state({
            "status": "error",
            "message": String(evaluation["errors"][0].get("message", "Template configuration contains errors.")),
        })
        return

    var config := build_config_payload()
    var response: Variant = controller.call("generate", config)
    if response is Dictionary and response.has("code"):
        var error_dict: Dictionary = response
        var message := String(error_dict.get("message", "Generation failed."))
        var guidance := _lookup_error_guidance(String(error_dict.get("code", "")))
        var composed := _compose_guidance_display(guidance)
        var hint := String(composed.get("text", ""))
        var tooltip := String(composed.get("tooltip", ""))
        if hint != "":
            message += "\n%s" % hint
        _update_preview_state({
            "status": "error",
            "message": message,
            "details": error_dict.get("details", {}),
            "tooltip": tooltip,
        })
        _update_seed_helper()
        return

    _update_preview_state({
        "status": "success",
        "message": String(response),
    })
    _update_seed_helper()
    _notify_configuration_changed()

func _on_seed_submitted(text: String) -> void:
    _seed_edit.text = text
    _on_preview_button_pressed()

func _refresh_metadata() -> void:
    var service := _get_metadata_service()
    if service == null:
        _metadata_summary.text = "Template strategy metadata unavailable."
        _notes_label.text = ""
        return

    var required := PackedStringArray()
    if service.has_method("get_required_keys"):
        required = service.call("get_required_keys", TEMPLATE_STRATEGY_ID)
    var optional: Dictionary = {}
    if service.has_method("get_optional_key_types"):
        optional = service.call("get_optional_key_types", TEMPLATE_STRATEGY_ID)

    var summary_parts: Array[String] = []
    if required.size() > 0:
        summary_parts.append("Required: %s" % _join_strings(required, ", "))
    if not optional.is_empty():
        var optional_keys := PackedStringArray()
        for key in optional.keys():
            optional_keys.append(String(key))
        optional_keys.sort()
        summary_parts.append("Optional: %s" % _join_strings(optional_keys, ", "))
    _metadata_summary.text = _join_strings(summary_parts, " | ")

    var notes := PackedStringArray()
    if service.has_method("get_default_notes"):
        notes = service.call("get_default_notes", TEMPLATE_STRATEGY_ID)
    if notes.size() > 0:
        _notes_label.text = _join_strings(notes, "\n")
    else:
        _notes_label.text = ""

func _update_seed_helper() -> void:
    var controller := _get_controller()
    var latest_metadata := {}
    if controller != null and controller.has_method("get_latest_generation_metadata"):
        latest_metadata = controller.call("get_latest_generation_metadata")
    var stream_hint := String(latest_metadata.get("rng_stream", ""))
    var seed_hint := String(latest_metadata.get("seed", ""))
    var helper_lines := ["Child seeds derive automatically as parent::token::occurrence."]
    if stream_hint != "" or seed_hint != "":
        helper_lines.append("Latest middleware seed: %s" % (seed_hint if seed_hint != "" else "—"))
        helper_lines.append("Latest middleware stream: %s" % (stream_hint if stream_hint != "" else "—"))
    _seed_helper.text = _join_strings(helper_lines, "\n")

func _rebuild_configuration_views() -> void:
    var evaluation := _evaluate_configuration()
    _render_token_tree(evaluation["structure"])
    _apply_validation_feedback(evaluation["errors"])

func _evaluate_configuration(seed_override: String = "") -> Dictionary:
    var template_string := _template_input.text
    var max_depth := int(_max_depth_spin.value)
    var seed_value := _seed_edit.text.strip_edges()
    if seed_override != "":
        seed_value = seed_override
    var errors: Array = []

    if max_depth <= 0:
        errors.append({
            "code": "invalid_max_depth",
            "message": "Configuration value for 'max_depth' must be greater than zero.",
            "target": "max_depth",
        })
        max_depth = 1

    var parse_result := _parse_sub_generators()
    errors.append_array(parse_result["errors"])
    var sub_generators: Dictionary = parse_result["definitions"]

    var structure := _build_token_structure(template_string, sub_generators, 0, max_depth, seed_value)
    errors.append_array(structure["errors"])

    return {
        "structure": structure["node"],
        "errors": errors,
    }

func _parse_sub_generators() -> Dictionary:
    var errors: Array = []
    var definitions: Dictionary = {}
    var text := _sub_generators_edit.text.strip_edges()
    if text == "":
        return {"errors": errors, "definitions": definitions}

    var json := JSON.new()
    var parse_error := json.parse(text)
    if parse_error != OK:
        errors.append({
            "code": "invalid_json",
            "message": "Child generator definitions must be valid JSON (error at line %d)." % (json.get_error_line()),
            "target": "sub_generators",
        })
        return {"errors": errors, "definitions": definitions}

    var data: Variant = json.data
    if typeof(data) != TYPE_DICTIONARY:
        errors.append({
            "code": "invalid_sub_generators_type",
            "message": "TemplateStrategy optional 'sub_generators' must be a Dictionary.",
            "target": "sub_generators",
        })
        return {"errors": errors, "definitions": definitions}

    definitions = (data as Dictionary).duplicate(true)
    return {"errors": errors, "definitions": definitions}

func _parse_sub_generator_dictionary() -> Dictionary:
    var result := _parse_sub_generators()
    return result["definitions"]

func _build_token_structure(
    template_string: String,
    sub_generators: Dictionary,
    depth: int,
    max_depth: int,
    parent_seed: String
) -> Dictionary:
    var structure := {
        "node_type": "template",
        "template": template_string,
        "depth": depth,
        "seed": parent_seed,
        "children": [],
    }
    var errors: Array = []

    var regex := _get_token_regex()
    var matches := regex.search_all(template_string)
    var token_counts: Dictionary = {}
    for match in matches:
        var token_raw := _extract_token(match)
        var token := token_raw.strip_edges()
        var start_index := match.get_start()
        var occurrence := int(token_counts.get(token, 0))
        token_counts[token] = occurrence + 1

        var token_node := {
            "node_type": "token",
            "token": token,
            "occurrence": occurrence,
            "depth": depth + 1,
            "seed": "%s::%s::%d" % [String(parent_seed), token, occurrence],
            "strategy": "",
            "display_name": "",
            "children": [],
            "errors": [],
        }

        if token == "":
            var empty_error := {
                "code": "empty_token",
                "message": "Template token at index %d must specify a sub-generator key." % start_index,
                "target": "template",
            }
            token_node["errors"].append(empty_error)
            errors.append(empty_error)
        elif not sub_generators.has(token):
            var missing_error := {
                "code": "missing_template_token",
                "message": "Template token '%s' does not have a configured sub-generator." % token,
                "target": "template",
            }
            token_node["errors"].append(missing_error)
            errors.append(missing_error)
        else:
            var generator_config_variant: Variant = sub_generators[token]
            if typeof(generator_config_variant) != TYPE_DICTIONARY:
                var type_error := {
                    "code": "invalid_config_type",
                    "message": "sub_generators['%s'] must be provided as a Dictionary." % token,
                    "target": "sub_generators",
                }
                token_node["errors"].append(type_error)
                errors.append(type_error)
            else:
                var generator_config: Dictionary = (generator_config_variant as Dictionary).duplicate(true)
                var strategy_id := String(generator_config.get("strategy", "")).strip_edges()
                token_node["strategy"] = strategy_id
                token_node["display_name"] = _resolve_strategy_display_name(strategy_id)

                if generator_config.has("seed"):
                    token_node["seed"] = String(generator_config["seed"])

                var inherited_max_depth := max_depth
                if generator_config.has("max_depth"):
                    inherited_max_depth = int(generator_config["max_depth"])
                    if inherited_max_depth <= 0:
                        var child_max_depth_error := {
                            "code": "invalid_max_depth",
                            "message": "Configuration value for 'max_depth' must be greater than zero.",
                            "target": "sub_generators",
                        }
                        token_node["errors"].append(child_max_depth_error)
                        errors.append(child_max_depth_error)

                if token_node["depth"] >= inherited_max_depth:
                    var depth_error := {
                        "code": "template_recursion_depth_exceeded",
                        "message": "Template expansion exceeded the allowed recursion depth (token '%s')." % token,
                        "target": "max_depth",
                    }
                    token_node["errors"].append(depth_error)
                    errors.append(depth_error)
                elif strategy_id == TEMPLATE_STRATEGY_ID:
                    var nested_template := String(generator_config.get("template_string", ""))
                    var nested_sub_generators_variant: Variant = generator_config.get("sub_generators", {})
                    var nested_sub_generators: Dictionary = {}
                    if nested_sub_generators_variant is Dictionary:
                        nested_sub_generators = (nested_sub_generators_variant as Dictionary).duplicate(true)
                    var nested := _build_token_structure(
                        nested_template,
                        nested_sub_generators,
                        token_node["depth"],
                        inherited_max_depth,
                        token_node["seed"],
                    )
                    token_node["children"].append(nested["node"])
                    errors.append_array(nested["errors"])
                elif strategy_id == "":
                    var missing_strategy_error := {
                        "code": "missing_strategy",
                        "message": "Child generator for token '%s' must provide a 'strategy' key." % token,
                        "target": "sub_generators",
                    }
                    token_node["errors"].append(missing_strategy_error)
                    errors.append(missing_strategy_error)
        structure["children"].append(token_node)
    return {"node": structure, "errors": errors}

func _render_token_tree(structure: Dictionary) -> void:
    _token_tree.clear()
    var root := _token_tree.create_item()
    if structure.is_empty():
        return
    var template_item := _token_tree.create_item(root)
    template_item.set_text(0, "Template")
    template_item.set_text(1, str(structure.get("depth", 0)))
    template_item.set_text(2, _resolve_strategy_display_name(TEMPLATE_STRATEGY_ID))
    template_item.set_text(3, String(structure.get("seed", "")))
    template_item.set_tooltip_text(0, structure.get("template", ""))
    template_item.collapsed = false
    _populate_token_children(template_item, structure.get("children", []))

func _populate_token_children(parent: TreeItem, children: Array) -> void:
    for child_dict in children:
        if not (child_dict is Dictionary):
            continue
        var child: Dictionary = child_dict
        if child.get("node_type", "") == "template":
            var template_item := _token_tree.create_item(parent)
            template_item.set_text(0, "Nested template")
            template_item.set_text(1, str(child.get("depth", 0)))
            template_item.set_text(2, _resolve_strategy_display_name(TEMPLATE_STRATEGY_ID))
            template_item.set_text(3, String(child.get("seed", "")))
            template_item.set_tooltip_text(0, child.get("template", ""))
            _populate_token_children(template_item, child.get("children", []))
            continue

        var token_item := _token_tree.create_item(parent)
        token_item.set_text(0, "[%s] (x%d)" % [String(child.get("token", "")), int(child.get("occurrence", 0)) + 1])
        token_item.set_text(1, str(child.get("depth", 0)))
        var display_name := String(child.get("display_name", ""))
        var strategy_id := String(child.get("strategy", ""))
        if display_name == "" and strategy_id != "":
            display_name = strategy_id.capitalize()
        token_item.set_text(2, display_name)
        token_item.set_tooltip_text(2, strategy_id if strategy_id != "" else "Unmapped token")
        token_item.set_text(3, String(child.get("seed", "")))

        var errors: Array = child.get("errors", [])
        if not errors.is_empty():
            token_item.set_custom_color(0, Color(0.8, 0.2, 0.2))
            var tooltips: Array[String] = []
            for error in errors:
                tooltips.append(String(error.get("message", "")))
            token_item.set_tooltip_text(0, _join_strings(tooltips, "\n"))
        _populate_token_children(token_item, child.get("children", []))

func _apply_validation_feedback(errors: Array) -> void:
    _validation_label.visible = false
    _validation_label.text = ""
    _validation_label.tooltip_text = ""
    _fix_it_label.visible = false
    _fix_it_label.text = ""
    _fix_it_label.tooltip_text = ""
    _set_control_highlight(_template_input, false)
    _set_control_highlight(_sub_generators_edit, false)
    _set_control_highlight(_max_depth_spin, false)

    if errors.is_empty():
        return

    var primary: Dictionary = {}
    if errors.size() > 0 and errors[0] is Dictionary:
        primary = errors[0]
    _validation_label.visible = true
    _validation_label.text = String(primary.get("message", "Template configuration invalid."))
    _validation_label.tooltip_text = _validation_label.text

    var hint_messages: Array[String] = []
    var hint_tooltips: Array[String] = []
    for error in errors:
        var guidance := _lookup_error_guidance(String(error.get("code", "")))
        if guidance.is_empty():
            continue
        var composed := _compose_guidance_display(guidance)
        var hint := String(composed.get("text", ""))
        if hint == "":
            continue
        if hint_messages.has(hint):
            continue
        var tooltip := String(composed.get("tooltip", ""))
        if tooltip != "":
            hint_tooltips.append(tooltip)
        hint_messages.append(hint)
    if not hint_messages.is_empty():
        _fix_it_label.visible = true
        _fix_it_label.text = _join_strings(hint_messages, "\n\n")
        if hint_tooltips.is_empty():
            _fix_it_label.tooltip_text = _fix_it_label.text
        else:
            _fix_it_label.tooltip_text = _join_strings(hint_tooltips, "\n\n")

    for error in errors:
        match String(error.get("target", "")):
            "template":
                _set_control_highlight(_template_input, true)
            "sub_generators":
                _set_control_highlight(_sub_generators_edit, true)
            "max_depth":
                _set_control_highlight(_max_depth_spin, true)

func _update_preview_state(payload: Dictionary) -> void:
    _preview_label.visible = false
    _preview_label.text = ""
    _preview_label.tooltip_text = ""
    _validation_label.tooltip_text = ""
    if payload == null:
        return
    var status := String(payload.get("status", ""))
    var message := String(payload.get("message", ""))
    if status == "success":
        _validation_label.visible = false
        _preview_label.visible = true
        _preview_label.text = "[b]Preview:[/b]\n%s" % message
        _preview_label.tooltip_text = message
    else:
        _validation_label.visible = true
        _validation_label.text = message
        var tooltip := String(payload.get("tooltip", message))
        if tooltip == "":
            tooltip = message
        _validation_label.tooltip_text = tooltip

func _lookup_error_guidance(code: String) -> Dictionary:
    if code == "" or code == "invalid_json":
        return {}
    var service := _get_metadata_service()
    if service == null:
        return {}
    if service.has_method("get_generator_error_guidance"):
        var guidance: Variant = service.call("get_generator_error_guidance", TEMPLATE_STRATEGY_ID, code)
        if guidance is Dictionary:
            return guidance
    if service.has_method("get_generator_error_hint"):
        var fallback := String(service.call("get_generator_error_hint", TEMPLATE_STRATEGY_ID, code))
        if fallback != "":
            return {"message": fallback}
    return {}

func _compose_guidance_display(guidance: Dictionary) -> Dictionary:
    if guidance.is_empty():
        return {"text": "", "tooltip": ""}
    var text_segments: Array[String] = []
    var tooltip_segments: Array[String] = []
    var message := String(guidance.get("message", ""))
    if message != "":
        text_segments.append(message)
        tooltip_segments.append(message)
    var remediation := String(guidance.get("remediation", ""))
    if remediation != "":
        var fix_line := "Try: %s" % remediation
        text_segments.append(fix_line)
        tooltip_segments.append(fix_line)
    var handbook_label := String(guidance.get("handbook_label", ""))
    if handbook_label != "":
        var anchor := String(guidance.get("handbook_anchor", ""))
        var handbook_line := "Handbook: %s" % handbook_label
        if anchor != "":
            handbook_line += " (#%s)" % anchor
            tooltip_segments.append("Platform GUI Handbook › %s (#%s)" % [handbook_label, anchor])
        else:
            tooltip_segments.append("Platform GUI Handbook › %s" % handbook_label)
        text_segments.append(handbook_line)
    return {
        "text": _join_strings(text_segments, "\n"),
        "tooltip": _join_strings(tooltip_segments, "\n"),
    }

func _track_default_modulate(control: Control) -> void:
    if control == null:
        return
    _control_default_modulates[control] = control.self_modulate

func _set_control_highlight(control: Control, highlight: bool) -> void:
    if control == null:
        return
    if highlight:
        control.self_modulate = _ERROR_TINT
    elif _control_default_modulates.has(control):
        control.self_modulate = _control_default_modulates[control]

func _notify_configuration_changed() -> void:
    if not is_inside_tree():
        return
    configuration_changed.emit()

func _resolve_strategy_display_name(strategy_id: String) -> String:
    if strategy_id == "":
        return ""
    var service := _get_metadata_service()
    if service == null:
        return strategy_id
    if service.has_method("get_strategy_metadata"):
        var metadata: Dictionary = service.call("get_strategy_metadata", strategy_id)
        if metadata.has("display_name"):
            return String(metadata["display_name"])
    return strategy_id

func _get_token_regex() -> RegEx:
    if _token_regex == null:
        _token_regex = RegEx.new()
        var error := _token_regex.compile(TOKEN_PATTERN)
        if error != OK:
            push_error("Failed to compile template token pattern: %s" % TOKEN_PATTERN)
    return _token_regex

func _extract_token(match: RegExMatch) -> String:
    if match.names.has("token"):
        return match.get_string("token")
    return match.get_string(1)

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

func _join_strings(values: Variant, separator: String) -> String:
    var combined := ""
    var is_first := true
    for value in values:
        var segment := String(value)
        if is_first:
            combined = segment
            is_first = false
        else:
            combined += "%s%s" % [separator, segment]
    return combined

func _is_object_valid(candidate: Object) -> bool:
    if candidate == null:
        return false
    if candidate is Node:
        return is_instance_valid(candidate)
    return true
