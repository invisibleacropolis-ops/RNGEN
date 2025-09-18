extends VBoxContainer

## Editor panel that assembles HybridStrategy pipelines for the Platform GUI.
##
## Artists can compose ordered step chains by dragging entries, tweak per-strategy
## forms, and assign $alias placeholders that HybridStrategy exposes to later
## template interpolation. The widget visualises the resulting seed derivations
## and RNG stream routing using the middleware metadata exposed by the
## RNGProcessor controller. Inline error handling maps middleware codes to
## metadata-driven guidance and highlights the failing step so debugging remains
## self contained inside the editor.

@export var controller_path: NodePath
@export var metadata_service_path: NodePath

signal configuration_changed

const HYBRID_STRATEGY_ID := "hybrid"
const _ERROR_TINT := Color(1.0, 0.9, 0.9, 1.0)
const _HIGHLIGHT_TINT := Color(0.85, 0.93, 1.0, 1.0)

const STRATEGY_PANEL_SCENES := {
    "wordlist": preload("res://addons/platform_gui/panels/wordlist/WordlistPanel.tscn"),
    "template": preload("res://addons/platform_gui/panels/template/TemplatePanel.tscn"),
    "markov": preload("res://addons/platform_gui/panels/markov/MarkovPanel.tscn"),
    "syllable_chain": preload("res://addons/platform_gui/panels/syllable_chain/SyllableChainPanel.tscn"),
}

class StepConfig:
    extends RefCounted

    var alias: String = ""
    var strategy_id: String = ""
    var panel: Control = null
    var error_code: String = ""

    func get_display_label(index: int) -> String:
        var alias_text := alias.strip_edges()
        var prefix := str(index + 1)
        if alias_text != "":
            return "%s • $%s (%s)" % [prefix, alias_text, strategy_id]
        return "%s • %s" % [prefix, strategy_id]

var _controller_override: Object = null
var _cached_controller: Object = null
var _metadata_service_override: Object = null
var _cached_metadata_service: Object = null
var _steps: Array[StepConfig] = []
var _strategy_panel_overrides: Dictionary = {}

@onready var _metadata_summary: Label = %MetadataSummary
@onready var _notes_label: Label = %NotesLabel
@onready var _strategy_selector: OptionButton = %StrategySelector
@onready var _add_step_button: Button = %AddStepButton
@onready var _remove_step_button: Button = %RemoveStepButton
@onready var _step_list: ItemList = %StepList
@onready var _alias_edit: LineEdit = %AliasEdit
@onready var _template_edit: TextEdit = %TemplateInput
@onready var _seed_edit: LineEdit = %SeedInput
@onready var _seed_helper: Label = %SeedHelper
@onready var _step_metadata_label: RichTextLabel = %StepMetadataLabel
@onready var _pipeline_tree: Tree = %PipelineTree
@onready var _panel_cache: Node = %StepPanelCache
@onready var _config_host: VBoxContainer = %StrategyConfigHost
@onready var _preview_button: Button = %PreviewButton
@onready var _preview_label: RichTextLabel = %PreviewOutput
@onready var _error_label: Label = %ErrorLabel
@onready var _hint_label: Label = %HintLabel
@onready var _details_label: RichTextLabel = %DetailLabel

func _ready() -> void:
    _step_list.allow_rearrange = true
    _step_list.item_selected.connect(_on_step_selected)
    _step_list.nothing_selected.connect(_on_step_deselected)
    _step_list.gui_input.connect(_on_step_list_gui_input)
    _add_step_button.pressed.connect(_on_add_step_pressed)
    _remove_step_button.pressed.connect(_on_remove_step_pressed)
    _strategy_selector.item_selected.connect(_on_strategy_option_changed)
    _alias_edit.text_changed.connect(_on_alias_changed)
    _template_edit.text_changed.connect(_on_template_changed)
    _seed_edit.text_changed.connect(_on_seed_changed)
    _seed_edit.text_submitted.connect(_on_seed_submitted)
    _preview_button.pressed.connect(_on_preview_button_pressed)
    %RefreshButton.pressed.connect(_on_refresh_pressed)
    _pipeline_tree.columns = 5
    _pipeline_tree.set_column_title(0, "Step")
    _pipeline_tree.set_column_title(1, "Alias")
    _pipeline_tree.set_column_title(2, "Strategy")
    _pipeline_tree.set_column_title(3, "Derived Seed")
    _pipeline_tree.set_column_title(4, "RNG Stream")
    _pipeline_tree.set_column_titles_visible(true)
    _refresh_metadata()
    _refresh_strategy_selector()
    _rebuild_pipeline_tree()
    _update_seed_helper()
    _update_preview_state(null)

func apply_config_payload(config: Dictionary) -> void:
    _clear_all_steps()
    var steps_variant := config.get("steps", [])
    if steps_variant is Array:
        for entry_variant in steps_variant:
            if typeof(entry_variant) != TYPE_DICTIONARY:
                continue
            var entry: Dictionary = entry_variant
            var step_config_variant := entry.get("config", {})
            if typeof(step_config_variant) != TYPE_DICTIONARY:
                continue
            var step_config: Dictionary = (step_config_variant as Dictionary).duplicate(true)
            var strategy_id := String(step_config.get("strategy", "")).strip_edges()
            if strategy_id == "":
                continue
            var step := StepConfig.new()
            step.alias = String(entry.get("store_as", ""))
            step.strategy_id = strategy_id
            step.panel = _instantiate_strategy_panel(strategy_id)
            _steps.append(step)
            _register_step_panel(step)
            if step.panel != null and step.panel.has_method("apply_config_payload"):
                step.panel.call_deferred("apply_config_payload", step_config)
    _refresh_step_list()
    _clear_config_host()
    _template_edit.text = String(config.get("template", ""))
    _seed_edit.text = String(config.get("seed", ""))
    _rebuild_pipeline_tree()
    _update_seed_helper()
    _notify_configuration_changed()

func describe_seed_propagation() -> Array:
    var ordered_steps := _get_steps_in_ui_order()
    var base_seed := _seed_edit.text.strip_edges()
    var result: Array = []
    for index in range(ordered_steps.size()):
        var step := ordered_steps[index]
        var alias_raw := step.alias.strip_edges()
        var alias := alias_raw
        if alias == "":
            alias = str(index)
        var derived_seed := base_seed if base_seed != "" else ""
        if derived_seed != "":
            derived_seed = "%s::step_%s" % [derived_seed, alias]
        else:
            derived_seed = "step_%s" % alias
        result.append({
            "index": index,
            "alias": alias,
            "strategy": step.strategy_id,
            "seed": derived_seed,
            "has_alias": alias_raw != "",
        })
    return result

func get_pipeline_seed() -> String:
    return _seed_edit.text.strip_edges()

func apply_step_config(alias: String, config: Dictionary) -> void:
    var target := _find_step_by_alias(alias)
    if target == null:
        return
    if target.panel != null and target.panel.has_method("apply_config_payload"):
        target.panel.call("apply_config_payload", config.duplicate(true))
    _rebuild_pipeline_tree()
    _notify_configuration_changed()

func set_controller_override(controller: Object) -> void:
    _controller_override = controller
    _cached_controller = null
    for step in _steps:
        if step.panel != null and step.panel.has_method("set_controller_override"):
            step.panel.call("set_controller_override", controller)
    _update_seed_helper()

func set_metadata_service_override(service: Object) -> void:
    _metadata_service_override = service
    _cached_metadata_service = null
    for step in _steps:
        if step.panel != null and step.panel.has_method("set_metadata_service_override"):
            step.panel.call("set_metadata_service_override", service)
    _refresh_metadata()

func set_strategy_panel_override(strategy_id: String, scene: PackedScene) -> void:
    if strategy_id == "":
        return
    if scene == null:
        _strategy_panel_overrides.erase(strategy_id)
        return
    _strategy_panel_overrides[strategy_id] = scene

func refresh() -> void:
    _refresh_metadata()
    _refresh_strategy_selector()
    for step in _steps:
        if step.panel != null and step.panel.has_method("refresh"):
            step.panel.call("refresh")
    _rebuild_pipeline_tree()
    _update_seed_helper()
    _notify_configuration_changed()

func build_config_payload() -> Dictionary:
    var steps_payload: Array = []
    for step in _get_steps_in_ui_order():
        var entry: Dictionary = {}
        var alias := step.alias.strip_edges()
        if alias != "":
            entry["store_as"] = alias
        var config := _collect_step_config(step)
        if config.is_empty():
            continue
        entry["config"] = config
        steps_payload.append(entry)
    var payload: Dictionary = {
        "strategy": HYBRID_STRATEGY_ID,
        "steps": steps_payload,
    }
    var template_text := _template_edit.text.strip_edges()
    if template_text != "":
        payload["template"] = template_text
    var seed_text := _seed_edit.text.strip_edges()
    if seed_text != "":
        payload["seed"] = seed_text
    return payload

func get_child_generator_definitions() -> Dictionary:
    var definitions: Dictionary = {}
    for step in _steps:
        var config := _collect_step_config(step)
        if config.is_empty():
            continue
        var alias := step.alias.strip_edges()
        if alias == "":
            continue
        definitions[alias] = config.duplicate(true)
    return definitions

func _on_refresh_pressed() -> void:
    refresh()

func _on_add_step_pressed() -> void:
    var strategy_id := _get_selected_strategy_id()
    if strategy_id == "":
        return
    var step := StepConfig.new()
    step.strategy_id = strategy_id
    step.panel = _instantiate_strategy_panel(strategy_id)
    _steps.append(step)
    _register_step_panel(step)
    _refresh_step_list()
    _select_step(step)
    _rebuild_pipeline_tree()
    _notify_configuration_changed()

func _on_remove_step_pressed() -> void:
    var selected := _get_selected_step()
    if selected == null:
        return
    _unregister_step_panel(selected)
    _steps.erase(selected)
    _refresh_step_list()
    _clear_config_host()
    _rebuild_pipeline_tree()
    _update_step_details(null)
    _notify_configuration_changed()

func _on_strategy_option_changed(_index: int) -> void:
    # No-op hook so tests can simulate menu selections before pressing Add.
    pass

func _on_step_selected(index: int) -> void:
    var step := _get_step_by_index(index)
    _mount_step_panel(step)
    _update_step_details(step)
    _highlight_active_step(step)

func _on_step_deselected() -> void:
    _update_step_details(null)
    _highlight_active_step(null)

func _on_step_list_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and not event.pressed:
        _rebuild_pipeline_tree()

func _on_alias_changed(text: String) -> void:
    var step := _get_selected_step()
    if step == null:
        return
    step.alias = text
    _refresh_step_list()
    _rebuild_pipeline_tree()
    _update_step_details(step)
    _notify_configuration_changed()

func _on_template_changed(_text: String) -> void:
    _rebuild_pipeline_tree()
    _notify_configuration_changed()

func _on_seed_changed(_text: String) -> void:
    _rebuild_pipeline_tree()
    _update_seed_helper()
    var step := _get_selected_step()
    _update_step_details(step)
    _notify_configuration_changed()

func _on_seed_submitted(text: String) -> void:
    _seed_edit.text = text
    _on_preview_button_pressed()

func _on_preview_button_pressed() -> void:
    var controller := _get_controller()
    if controller == null:
        _update_preview_state({
            "status": "error",
            "message": "RNGProcessor controller unavailable.",
        })
        return
    var payload := build_config_payload()
    if payload["steps"].is_empty():
        _update_preview_state({
            "status": "error",
            "message": "Configure at least one pipeline step before previewing.",
        })
        return
    var response: Variant = controller.call("generate", payload)
    if response is Dictionary and response.has("code"):
        _apply_error_state(response)
        _update_seed_helper()
        return
    _clear_step_error_states()
    _update_preview_state({
        "status": "success",
        "message": String(response),
    })
    _update_seed_helper()
    _rebuild_pipeline_tree()
    _notify_configuration_changed()

func _collect_step_config(step: StepConfig) -> Dictionary:
    if step == null:
        return {}
    if step.panel == null:
        return {}
    if step.panel.has_method("build_config_payload"):
        var config_variant: Variant = step.panel.call("build_config_payload")
        if config_variant is Dictionary:
            var config: Dictionary = config_variant
            config.erase("seed")
            return config.duplicate(true)
    return {}

func _instantiate_strategy_panel(strategy_id: String) -> Control:
    var scene: PackedScene = _strategy_panel_overrides.get(strategy_id, null)
    if scene == null:
        if not STRATEGY_PANEL_SCENES.has(strategy_id):
            return null
        scene = STRATEGY_PANEL_SCENES[strategy_id]
    var panel := scene.instantiate()
    if panel.has_method("set_controller_override"):
        panel.call("set_controller_override", _get_controller())
    if panel.has_method("set_metadata_service_override"):
        panel.call("set_metadata_service_override", _get_metadata_service())
    if panel.has_method("refresh"):
        panel.call_deferred("refresh")
    return panel

func _register_step_panel(step: StepConfig) -> void:
    if step.panel == null:
        return
    _panel_cache.add_child(step.panel)
    step.panel.hide()

func _unregister_step_panel(step: StepConfig) -> void:
    if step.panel == null:
        return
    if step.panel.get_parent() != null:
        step.panel.get_parent().remove_child(step.panel)
    step.panel.queue_free()
    step.panel = null

func _mount_step_panel(step: StepConfig) -> void:
    _clear_config_host()
    if step == null or step.panel == null:
        return
    if step.panel.get_parent() != null:
        step.panel.get_parent().remove_child(step.panel)
    _config_host.add_child(step.panel)
    step.panel.show()

func _clear_config_host() -> void:
    for child in _config_host.get_children():
        _config_host.remove_child(child)
        if child is Control:
            child.hide()
            _panel_cache.add_child(child)

func _get_steps_in_ui_order() -> Array[StepConfig]:
    var ordered: Array[StepConfig] = []
    for index in range(_step_list.item_count):
        var step: StepConfig = _step_list.get_item_metadata(index)
        if step != null:
            ordered.append(step)
    if ordered.size() == _steps.size():
        _steps = ordered
    return ordered

func _get_step_by_index(index: int) -> StepConfig:
    if index < 0 or index >= _step_list.item_count:
        return null
    var step: StepConfig = _step_list.get_item_metadata(index)
    return step

func _get_selected_step() -> StepConfig:
    var selected := _step_list.get_selected_items()
    if selected.is_empty():
        return null
    return _get_step_by_index(selected[0])

func _get_selected_strategy_id() -> String:
    if _strategy_selector.item_count == 0:
        return ""
    var index := _strategy_selector.get_selected_id()
    if index == -1:
        index = _strategy_selector.get_selected()
    if index < 0 or index >= _strategy_selector.item_count:
        return ""
    return String(_strategy_selector.get_item_metadata(index))

func _refresh_step_list() -> void:
    _step_list.clear()
    for index in range(_steps.size()):
        var step := _steps[index]
        var label := step.get_display_label(index)
        _step_list.add_item(label)
        _step_list.set_item_metadata(index, step)
        if step.error_code != "":
            _step_list.set_item_custom_bg_color(index, _ERROR_TINT)
    var selected := _get_selected_step()
    if selected != null:
        var new_index := _steps.find(selected)
        if new_index != -1:
            _step_list.select(new_index)

func _update_step_details(step: StepConfig) -> void:
    if step == null:
        _alias_edit.editable = false
        _alias_edit.text = ""
        _step_metadata_label.bbcode_text = ""
        return
    _alias_edit.editable = true
    _alias_edit.text = step.alias
    _step_metadata_label.bbcode_text = _format_step_metadata(step)

func _highlight_active_step(step: StepConfig) -> void:
    for index in range(_step_list.item_count):
        var metadata: StepConfig = _step_list.get_item_metadata(index)
        if metadata == null:
            continue
        if metadata == step:
            _step_list.set_item_custom_bg_color(index, _HIGHLIGHT_TINT)
        elif metadata.error_code != "":
            _step_list.set_item_custom_bg_color(index, _ERROR_TINT)
        else:
            _step_list.set_item_custom_bg_color(index, Color.WHITE)

func _clear_step_error_states() -> void:
    for step in _steps:
        step.error_code = ""
    _refresh_step_list()
    _highlight_active_step(_get_selected_step())
    _error_label.visible = false
    _hint_label.visible = false
    _details_label.visible = false
    _hint_label.tooltip_text = ""

func _apply_error_state(error_dict: Dictionary) -> void:
    var code := String(error_dict.get("code", "hybrid_error"))
    var message := String(error_dict.get("message", "Generation failed."))
    var details: Dictionary = error_dict.get("details", {})
    var alias := String(details.get("alias", ""))
    var targeted_step := _find_step_by_alias(alias)
    if targeted_step == null and alias.is_empty() and details.has("index"):
        targeted_step = _get_step_by_runtime_index(details.get("index"))
    var guidance := _lookup_error_guidance(code, targeted_step)
    var composed := _compose_guidance_display(guidance)
    var hint := String(composed.get("text", ""))
    var tooltip := String(composed.get("tooltip", ""))
    if targeted_step != null:
        targeted_step.error_code = code
    _refresh_step_list()
    _highlight_active_step(targeted_step)
    var detail_lines := []
    for key in details.keys():
        detail_lines.append("[b]%s[/b]: %s" % [String(key), _stringify_value(details[key])])
    _error_label.visible = true
    _error_label.text = message
    if hint != "":
        _hint_label.visible = true
        _hint_label.text = hint
        _hint_label.tooltip_text = tooltip if tooltip != "" else hint
    else:
        _hint_label.visible = false
        _hint_label.text = ""
        _hint_label.tooltip_text = ""
    if not detail_lines.is_empty():
        _details_label.visible = true
        _details_label.bbcode_text = "\n".join(detail_lines)
    else:
        _details_label.visible = false
        _details_label.bbcode_text = ""
    _update_preview_state({
        "status": "error",
        "message": message,
        "tooltip": tooltip if tooltip != "" else message,
    })

func _find_step_by_alias(alias: String) -> StepConfig:
    var trimmed := alias.strip_edges()
    if trimmed == "":
        return null
    for step in _steps:
        if step.alias.strip_edges() == trimmed:
            return step
    return null

func _get_step_by_runtime_index(index_value: Variant) -> StepConfig:
    var index := int(index_value)
    if index < 0 or index >= _steps.size():
        return null
    return _steps[index]

func _lookup_error_guidance(code: String, targeted_step: StepConfig) -> Dictionary:
    var service := _get_metadata_service()
    if service == null:
        return {}
    var guidance := {}
    if targeted_step != null and targeted_step.strategy_id != "":
        if service.has_method("get_generator_error_guidance"):
            var targeted_guidance: Variant = service.call("get_generator_error_guidance", targeted_step.strategy_id, code)
            if targeted_guidance is Dictionary and not (targeted_guidance as Dictionary).is_empty():
                guidance = targeted_guidance
    if guidance.is_empty() and service.has_method("get_generator_error_guidance"):
        var fallback_guidance: Variant = service.call("get_generator_error_guidance", HYBRID_STRATEGY_ID, code)
        if fallback_guidance is Dictionary:
            guidance = fallback_guidance
    if guidance.is_empty() and service.has_method("get_generator_error_hint"):
        var hint := String(service.call("get_generator_error_hint", HYBRID_STRATEGY_ID, code))
        if hint != "":
            guidance = {"message": hint}
    return guidance

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
        "text": "\n".join(text_segments),
        "tooltip": "\n".join(tooltip_segments),
    }

func _format_step_metadata(step: StepConfig) -> String:
    var base_seed := _seed_edit.text.strip_edges()
    var alias := step.alias.strip_edges()
    if alias == "":
        alias = str(_steps.find(step))
    var derived_seed := "%s::step_%s" % [base_seed, alias] if base_seed != "" else "step_%s" % alias
    var stream := _derive_stream_hint(alias)
    var lines := ["[b]Seed[/b]: %s" % derived_seed]
    if stream != "":
        lines.append("[b]Stream[/b]: %s" % stream)
    return "\n".join(lines)

func _derive_stream_hint(alias: String) -> String:
    var controller := _get_controller()
    if controller == null:
        return ""
    if not controller.has_method("get_latest_generation_metadata"):
        return ""
    var metadata: Dictionary = controller.call("get_latest_generation_metadata")
    var stream := String(metadata.get("rng_stream", ""))
    if stream == "":
        return ""
    return "%s::step_%s" % [stream, alias]

func _update_preview_state(state: Dictionary) -> void:
    if state == null:
        _preview_label.visible = false
        return
    var status := String(state.get("status", ""))
    var message := String(state.get("message", ""))
    var tooltip := String(state.get("tooltip", message))
    if tooltip == "":
        tooltip = message
    if status == "success":
        _preview_label.visible = true
        _preview_label.text = message
        _preview_label.self_modulate = Color(0.85, 1.0, 0.85, 1.0)
        _preview_label.tooltip_text = message
    elif status == "error":
        _preview_label.visible = true
        _preview_label.text = message
        _preview_label.self_modulate = Color(1.0, 0.85, 0.85, 1.0)
        _preview_label.tooltip_text = tooltip
    else:
        _preview_label.visible = false
        _preview_label.tooltip_text = ""

func _refresh_metadata() -> void:
    var service := _get_metadata_service()
    if service == null:
        _metadata_summary.text = "Hybrid strategy metadata unavailable."
        _notes_label.text = ""
        return
    var required := PackedStringArray()
    if service.has_method("get_required_keys"):
        required = service.call("get_required_keys", HYBRID_STRATEGY_ID)
    var optional: Dictionary = {}
    if service.has_method("get_optional_key_types"):
        optional = service.call("get_optional_key_types", HYBRID_STRATEGY_ID)
    var notes := PackedStringArray()
    if service.has_method("get_default_notes"):
        notes = service.call("get_default_notes", HYBRID_STRATEGY_ID)
    var parts := []
    if required.size() > 0:
        parts.append("Required: %s" % ", ".join(required))
    if not optional.is_empty():
        var keys := PackedStringArray()
        for key in optional.keys():
            keys.append(String(key))
        keys.sort()
        parts.append("Optional: %s" % ", ".join(keys))
    _metadata_summary.text = " | ".join(parts)
    if notes.size() > 0:
        _notes_label.text = "\n".join(notes)
    else:
        _notes_label.text = ""

func _refresh_strategy_selector() -> void:
    _strategy_selector.clear()
    var index := 0
    for strategy_id in STRATEGY_PANEL_SCENES.keys():
        _strategy_selector.add_item(strategy_id.capitalize())
        _strategy_selector.set_item_metadata(index, strategy_id)
        index += 1
    if _strategy_selector.item_count > 0:
        _strategy_selector.select(0)

func _rebuild_pipeline_tree() -> void:
    _pipeline_tree.clear()
    var root := _pipeline_tree.create_item()
    var base_seed := _seed_edit.text.strip_edges()
    var controller := _get_controller()
    var stream_hint := ""
    if controller != null and controller.has_method("get_latest_generation_metadata"):
        var metadata: Dictionary = controller.call("get_latest_generation_metadata")
        stream_hint = String(metadata.get("rng_stream", ""))
    var pipeline_item := _pipeline_tree.create_item(root)
    pipeline_item.set_text(0, "Hybrid Pipeline")
    pipeline_item.set_text(1, base_seed if base_seed != "" else "auto-derived")
    pipeline_item.set_text(2, HYBRID_STRATEGY_ID)
    pipeline_item.set_text(3, base_seed if base_seed != "" else "")
    pipeline_item.set_text(4, stream_hint)
    var ordered_steps := _get_steps_in_ui_order()
    for index in range(ordered_steps.size()):
        var step := ordered_steps[index]
        var alias := step.alias.strip_edges()
        if alias == "":
            alias = str(index)
        var step_item := _pipeline_tree.create_item(pipeline_item)
        step_item.set_text(0, "%d" % (index + 1))
        step_item.set_text(1, "$%s" % alias)
        step_item.set_text(2, step.strategy_id)
        var derived_seed := base_seed.strip_edges()
        if derived_seed != "":
            step_item.set_text(3, "%s::step_%s" % [derived_seed, alias])
        else:
            step_item.set_text(3, "step_%s" % alias)
        if stream_hint != "":
            step_item.set_text(4, "%s::step_%s" % [stream_hint, alias])

func _clear_all_steps() -> void:
    for step in _steps:
        _unregister_step_panel(step)
    _steps.clear()
    if _step_list != null:
        _step_list.clear()
    _clear_config_host()

func _notify_configuration_changed() -> void:
    if not is_inside_tree():
        return
    configuration_changed.emit()

func _update_seed_helper() -> void:
    var controller := _get_controller()
    var metadata := {}
    if controller != null and controller.has_method("get_latest_generation_metadata"):
        metadata = controller.call("get_latest_generation_metadata")
    var lines := ["Hybrid steps derive seeds as pipeline_seed::step_$alias."]
    var last_seed := String(metadata.get("seed", ""))
    var stream := String(metadata.get("rng_stream", ""))
    if last_seed != "" or stream != "":
        lines.append("Latest middleware seed: %s" % (last_seed if last_seed != "" else "—"))
        lines.append("Latest middleware stream: %s" % (stream if stream != "" else "—"))
    _seed_helper.text = "\n".join(lines)

func _select_step(step: StepConfig) -> void:
    var index := _steps.find(step)
    if index == -1:
        return
    _step_list.select(index)
    _mount_step_panel(step)
    _update_step_details(step)
    _highlight_active_step(step)

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
    return candidate != null and is_instance_valid(candidate)

func _stringify_value(value: Variant) -> String:
    match typeof(value):
        TYPE_DICTIONARY, TYPE_ARRAY:
            return JSON.stringify(value, "  ")
        _:
            return String(value)
