extends VBoxContainer

## Platform GUI panel that configures the SyllableChainStrategy.
##
## The widget mirrors the structure of the word list panel: it discovers
## available SyllableSetResource assets, exposes metadata provided by the
## middleware, and offers deterministic previews through the RNGProcessor
## controller. Artists can drop the scene into existing editor hierarchies
## and wire up controller/metadata service paths without touching engine
## singletons during authoring.

@export var controller_path: NodePath
@export var metadata_service_path: NodePath

const SyllableSetResource := preload("res://name_generator/resources/SyllableSetResource.gd")
const FOCUS_STYLE := preload("res://addons/platform_gui/themes/focus_highlight.tres")

var _resource_list: ItemList= null
var _resource_summary_label: Label= null
var _require_middle_toggle: CheckButton= null
var _middle_min_spin: SpinBox= null
var _middle_max_spin: SpinBox= null
var _min_length_spin: SpinBox= null
var _refresh_button: Button = null
var _regex_preset_container: VBoxContainer= null
var _seed_edit: LineEdit= null
var _preview_button: Button= null
var _preview_label: RichTextLabel= null
var _validation_label: Label= null
var _metadata_summary: Label= null
var _notes_label: Label= null

var _controller_override: Object = null
var _cached_controller: Object = null
var _metadata_service_override: Object = null
var _cached_metadata_service: Object = null
var _resource_catalog_override: Array = []
var _resource_cache: Array = []
var _regex_presets: Dictionary = {}
var _control_default_modulates: Dictionary = {}

const _ERROR_TINT := Color(1.0, 0.85, 0.85, 1.0)

const REGEX_PRESETS := [
	{
		"id": "collapse_triplicate_letters",
		"label": "Collapse triple letters",
		"description": "Replace three or more repeated letters with a doublet.",
		"rules": [
			{"pattern": "([A-Za-z])\\1{2,}", "replacement": "\\1\\1"},
		],
	},
	{
		"id": "trim_apostrophes",
		"label": "Trim stray apostrophes",
		"description": "Remove leading/trailing apostrophes left behind by joins.",
		"rules": [
			{"pattern": "^'+", "replacement": ""},
			{"pattern": "'+$", "replacement": ""},
		],
	},
	{
		"id": "normalise_separators",
		"label": "Normalise separators",
		"description": "Swap multiple separators for a single hyphen and strip spaces.",
		"rules": [
			{"pattern": "[ _-]{2,}", "replacement": "-"},
			{"pattern": "\\s+-", "replacement": "-"},
			{"pattern": "-\\s+", "replacement": "-"},
		],
	},
]


func _ensure_nodes_ready() -> void:
	if _resource_list == null:
		_resource_list = get_node("%ResourceList") as ItemList
	if _resource_summary_label == null:
		_resource_summary_label = get_node("%ResourceSummary") as Label
	if _require_middle_toggle == null:
		_require_middle_toggle = get_node("%RequireMiddle") as CheckButton
	if _middle_min_spin == null:
		_middle_min_spin = get_node("%MiddleMinSpin") as SpinBox
	if _middle_max_spin == null:
		_middle_max_spin = get_node("%MiddleMaxSpin") as SpinBox
	if _min_length_spin == null:
		_min_length_spin = get_node("%MinLengthSpin") as SpinBox
	if _refresh_button == null:
		_refresh_button = get_node_or_null("%RefreshButton") as Button
		if _refresh_button == null:
			_refresh_button = get_node_or_null("Header/RefreshButton") as Button
	if _regex_preset_container == null:
		_regex_preset_container = get_node("%RegexPresetContainer") as VBoxContainer
	if _seed_edit == null:
		_seed_edit = get_node("%SeedInput") as LineEdit
	if _preview_button == null:
		_preview_button = get_node("%PreviewButton") as Button
	if _preview_label == null:
		_preview_label = get_node("%PreviewOutput") as RichTextLabel
	if _validation_label == null:
		_validation_label = get_node("%ValidationLabel") as Label
	if _metadata_summary == null:
		_metadata_summary = get_node("%MetadataSummary") as Label
	if _notes_label == null:
		_notes_label = get_node("%NotesLabel") as Label
func _ready() -> void:
	_ensure_nodes_ready()
	if _preview_button != null:
		_preview_button.pressed.connect(_on_preview_button_pressed)
	else:
		push_warning("Preview button node missing; preview action disabled.")
	if _refresh_button != null:
		_refresh_button.pressed.connect(_on_refresh_pressed)
	else:
		push_warning("Refresh button node missing; automatic refresh disabled.")
	_resource_list.item_selected.connect(_on_resource_selected)
	_require_middle_toggle.toggled.connect(_on_require_middle_toggled)
	_seed_edit.text_submitted.connect(_on_seed_submitted)
	_build_regex_preset_controls()
	_track_default_modulate(_resource_list)
	_track_default_modulate(_middle_min_spin)
	_track_default_modulate(_middle_max_spin)
	_refresh_metadata()
	_refresh_resource_catalog()
	_update_preview_state(null)
func set_controller_override(controller: Object) -> void:
	_ensure_nodes_ready()
	_controller_override = controller
	_cached_controller = null

func set_metadata_service_override(service: Object) -> void:
	_ensure_nodes_ready()
	_metadata_service_override = service
	_cached_metadata_service = null

func set_resource_catalog_override(entries: Array) -> void:
	_ensure_nodes_ready()
	_resource_catalog_override = entries.duplicate(true)
	_refresh_resource_catalog()

func refresh() -> void:
	_ensure_nodes_ready()
	_refresh_metadata()
	_refresh_resource_catalog()

func build_config_payload() -> Dictionary:
	_ensure_nodes_ready()
	var config: Dictionary = {
		"strategy": "syllable",
	}
	var path := _get_selected_resource_path()
	if path != "":
		config["syllable_set_path"] = path
	config["require_middle"] = _require_middle_toggle.button_pressed

	var min_middle := int(_middle_min_spin.value)
	var max_middle := int(_middle_max_spin.value)
	config["middle_syllables"] = {"min": min_middle, "max": max_middle}

	var min_length := int(_min_length_spin.value)
	if min_length > 0:
		config["min_length"] = min_length

	var seed_value := _seed_edit.text.strip_edges()
	if seed_value != "":
		config["seed"] = seed_value

	var rules := _collect_selected_regex_rules()
	if not rules.is_empty():
		config["post_processing_rules"] = rules

	return config

func get_selected_resource_path() -> String:
	_ensure_nodes_ready()
	return _get_selected_resource_path()

func _on_refresh_pressed() -> void:
	_ensure_nodes_ready()
	refresh()

func _on_resource_selected(_index: int) -> void:
	_ensure_nodes_ready()
	_update_selected_resource_summary()

func _on_require_middle_toggled(pressed: bool) -> void:
	_ensure_nodes_ready()
	if pressed and _middle_min_spin.value < 1:
		_middle_min_spin.value = 1
	if pressed and _middle_max_spin.value < 1:
		_middle_max_spin.value = 1

func _on_seed_submitted(text: String) -> void:
	_ensure_nodes_ready()
	_seed_edit.text = text
	_on_preview_button_pressed()

func _build_regex_preset_controls() -> void:
	_ensure_nodes_ready()
	for child in _regex_preset_container.get_children():
		child.queue_free()
	_regex_presets.clear()

	for preset in REGEX_PRESETS:
		if not (preset is Dictionary):
			continue
		var identifier := String(preset.get("id", ""))
		if identifier == "":
			continue
		var button := CheckBox.new()
		button.text = String(preset.get("label", identifier.capitalize()))
		button.tooltip_text = String(preset.get("description", ""))
		button.focus_mode = Control.FOCUS_ALL
		button.theme_override_styles["focus"] = FOCUS_STYLE
		_regex_preset_container.add_child(button)
		_regex_presets[identifier] = {
			"definition": preset,
			"control": button,
		}

func _refresh_metadata() -> void:
	_ensure_nodes_ready()
	var service := _get_metadata_service()
	if service == null:
		_metadata_summary.text = "Syllable strategy metadata unavailable."
		_notes_label.text = ""
		return

	var required_variant: Variant = PackedStringArray()
	if service.has_method("get_required_keys"):
		required_variant = service.call("get_required_keys", "syllable")
	var optional: Dictionary = {}
	if service.has_method("get_optional_key_types"):
		optional = service.call("get_optional_key_types", "syllable")
	var notes_variant: Variant = PackedStringArray()
	if service.has_method("get_default_notes"):
		notes_variant = service.call("get_default_notes", "syllable")

	var required_list: Array[String] = []
	if required_variant is PackedStringArray:
		for value in required_variant:
			required_list.append(String(value))
	elif required_variant is Array:
		for value in required_variant:
			required_list.append(String(value))

	var summary: Array[String] = []
	if not required_list.is_empty():
		summary.append("Requires: %s" % _join_strings(required_list, ", "))
	if optional is Dictionary and not optional.is_empty():
		var optional_strings: Array[String] = []
		for key in optional.keys():
			var variant_type := int(optional[key])
			optional_strings.append("%s (%s)" % [key, type_string(variant_type)])
		optional_strings.sort()
		summary.append("Optional: %s" % _join_strings(optional_strings, ", "))
	_metadata_summary.text = _join_strings(summary, " | ")

	var notes: Array[String] = []
	if notes_variant is PackedStringArray:
		for value in notes_variant:
			notes.append(String(value))
	elif notes_variant is Array:
		for value in notes_variant:
			notes.append(String(value))

	if not notes.is_empty():
		_notes_label.text = _join_strings(notes, "\n")
	else:
		_notes_label.text = ""

func _refresh_resource_catalog() -> void:
	_ensure_nodes_ready()
	_resource_list.clear()
	_resource_cache.clear()
	_resource_summary_label.text = "Select a syllable set to review its details."

	var descriptors: Array = []
	if not _resource_catalog_override.is_empty():
		descriptors = _resource_catalog_override.duplicate(true)
	else:
		descriptors = _discover_syllable_resources()

	descriptors.sort_custom(func(a, b):
		var left := String(a.get("display_name", a.get("path", "")))
		var right := String(b.get("display_name", b.get("path", "")))
		return left.nocasecmp_to(right) < 0
	)

	for descriptor in descriptors:
		if not (descriptor is Dictionary):
			continue
		var display_name := String(descriptor.get("display_name", descriptor.get("path", "")))
		var path := String(descriptor.get("path", ""))
		if path == "":
			continue

		var metadata := {
			"path": path,
			"locale": String(descriptor.get("locale", "")),
			"domain": String(descriptor.get("domain", "")),
			"prefix_count": int(descriptor.get("prefix_count", 0)),
			"middle_count": int(descriptor.get("middle_count", 0)),
			"suffix_count": int(descriptor.get("suffix_count", 0)),
			"allow_empty_middle": bool(descriptor.get("allow_empty_middle", true)),
		}

		var detail_parts: Array[String] = []
		if metadata["locale"] != "":
			detail_parts.append(metadata["locale"])
		if metadata["domain"] != "":
			detail_parts.append(metadata["domain"])
		var detail_suffix := _join_strings(detail_parts, " · ")
		var counts := "P:%d | M:%d | S:%d" % [metadata["prefix_count"], metadata["middle_count"], metadata["suffix_count"]]

		var line := display_name
		if detail_suffix != "":
			line += " — %s" % detail_suffix
		line += " (%s)" % counts

		var item_index := _resource_list.add_item(line)
		_resource_list.set_item_metadata(item_index, metadata)
		var tooltip_lines: Array[String] = [
			"Path: %s" % path,
			"Locale: %s" % (metadata["locale"] if metadata["locale"] != "" else "—"),
			"Domain: %s" % (metadata["domain"] if metadata["domain"] != "" else "—"),
			"Prefixes: %d" % metadata["prefix_count"],
			"Middles: %d" % metadata["middle_count"],
			"Suffixes: %d" % metadata["suffix_count"],
		]
		if not metadata["allow_empty_middle"] and metadata["middle_count"] > 0:
			tooltip_lines.append("Requires at least one middle syllable.")
		_resource_list.set_item_tooltip(item_index, _join_strings(tooltip_lines, "\n"))
		_resource_cache.append(metadata)

	if _resource_list.item_count == 0:
		_resource_list.add_item("No SyllableSetResource assets found.")
		_resource_list.set_item_disabled(0, true)

func _discover_syllable_resources() -> Array:
	_ensure_nodes_ready()
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
				var resource_path: String = path.path_join(entry)
				if not ResourceLoader.exists(resource_path):
					entry = dir.get_next()
					continue
				var resource: Resource = ResourceLoader.load(resource_path)
				if resource == null or not (resource is SyllableSetResource):
					entry = dir.get_next()
					continue
				var syllable_set: SyllableSetResource = resource
				results.append({
					"path": resource_path,
					"display_name": _derive_display_name(resource_path),
					"locale": syllable_set.locale,
					"domain": syllable_set.domain,
					"prefix_count": syllable_set.prefixes.size(),
					"middle_count": syllable_set.middles.size(),
					"suffix_count": syllable_set.suffixes.size(),
					"allow_empty_middle": syllable_set.allow_empty_middle,
				})
			entry = dir.get_next()
		dir.list_dir_end()
	return results

func _derive_display_name(path: String) -> String:
	_ensure_nodes_ready()
	var segments: PackedStringArray = path.split("/")
	var filename := String(path)
	if segments.size() > 0:
		filename = segments[segments.size() - 1]
	var trimmed := filename.replace(".tres", "").replace(".res", "")
	return trimmed.capitalize()

func _on_preview_button_pressed() -> void:
	_ensure_nodes_ready()
	var path := _get_selected_resource_path()
	if path == "":
		_update_preview_state({
			"status": "error",
			"message": "Select a syllable set before requesting a preview.",
			"highlight_resource": true,
		})
		return

	var controller := _get_controller()
	if controller == null:
		_update_preview_state({
			"status": "error",
			"message": "RNGProcessor controller unavailable.",
		})
		return

	var config := build_config_payload()
	if int(config["middle_syllables"].get("min", 0)) > int(config["middle_syllables"].get("max", 0)):
		_update_preview_state({
			"status": "error",
			"message": "Middle syllable minimum must be less than or equal to the maximum.",
			"highlight_range": true,
		})
		return

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
			"highlight_resource": String(error_dict.get("code", "")) == "missing_resource",
			"highlight_range": _should_highlight_range(error_dict.get("code", "")),
			"tooltip": tooltip,
		})
		return

	var output_text := String(response)
	_update_preview_state({
		"status": "success",
		"message": output_text,
	})

func _lookup_error_guidance(code: String) -> Dictionary:
	_ensure_nodes_ready()
	if code == "":
		return {}
	var service := _get_metadata_service()
	if service == null:
		return {}
	if service.has_method("get_generator_error_guidance"):
		var guidance: Variant = service.call("get_generator_error_guidance", "syllable", code)
		if guidance is Dictionary:
			return guidance
	if service.has_method("get_generator_error_hint"):
		var fallback := String(service.call("get_generator_error_hint", "syllable", code))
		if fallback != "":
			return {"message": fallback}
	return {}

func _should_highlight_range(code: String) -> bool:
	_ensure_nodes_ready()
	match code:
		"invalid_middle_range":
			return true
		"middle_syllables_not_available":
			return true
		"missing_required_middles":
			return true
		_:
			return false

func _update_preview_state(payload: Variant) -> void:
	_ensure_nodes_ready()
	_preview_label.visible = false
	_preview_label.text = ""
	_preview_label.tooltip_text = ""
	_validation_label.visible = false
	_validation_label.text = ""
	_validation_label.tooltip_text = ""
	_set_control_highlight(_resource_list, false)
	_set_control_highlight(_middle_min_spin, false)
	_set_control_highlight(_middle_max_spin, false)

	if payload == null or not (payload is Dictionary):
		return

	var dictionary: Dictionary = payload
	var status := String(dictionary.get("status", ""))
	var message := String(dictionary.get("message", ""))
	if status == "success":
		_preview_label.visible = true
		_preview_label.text = "[b]Preview:[/b]\n%s" % message
		_preview_label.tooltip_text = message
	else:
		_validation_label.visible = true
		_validation_label.text = message
		var tooltip := String(dictionary.get("tooltip", message))
		if tooltip == "":
			tooltip = message
		_validation_label.tooltip_text = tooltip
		if bool(dictionary.get("highlight_resource", false)):
			_set_control_highlight(_resource_list, true)
		if bool(dictionary.get("highlight_range", false)):
			_set_control_highlight(_middle_min_spin, true)
			_set_control_highlight(_middle_max_spin, true)

func _compose_guidance_display(guidance: Dictionary) -> Dictionary:
	_ensure_nodes_ready()
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

func _update_selected_resource_summary() -> void:
	_ensure_nodes_ready()
	var metadata := _get_selected_resource_metadata()
	if metadata.is_empty():
		_resource_summary_label.text = "Select a syllable set to review its details."
		return

	var lines: Array[String] = [
		"Path: %s" % metadata["path"],
		"Locale: %s" % (metadata["locale"] if metadata["locale"] != "" else "—"),
		"Domain: %s" % (metadata["domain"] if metadata["domain"] != "" else "—"),
		"Prefixes: %d" % metadata["prefix_count"],
		"Middles: %d" % metadata["middle_count"],
		"Suffixes: %d" % metadata["suffix_count"],
	]
	if not metadata["allow_empty_middle"] and metadata["middle_count"] > 0:
		lines.append("Requires at least one middle syllable.")
	_resource_summary_label.text = _join_strings(lines, "\n")

	var available_middles := int(metadata["middle_count"])
	if available_middles > _middle_max_spin.max_value:
		_middle_max_spin.max_value = available_middles
	_middle_min_spin.max_value = _middle_max_spin.max_value

	if _middle_min_spin.value > _middle_min_spin.max_value:
		_middle_min_spin.value = _middle_min_spin.max_value
	if _middle_max_spin.value < _middle_min_spin.value:
		_middle_max_spin.value = _middle_min_spin.value

func _collect_selected_regex_rules() -> Array:
	_ensure_nodes_ready()
	var rules: Array = []
	for identifier in _regex_presets.keys():
		var entry: Dictionary = _regex_presets[identifier]
		var control: CheckBox = entry.get("control", null)
		if control == null or not control.button_pressed:
			continue
		var definition: Dictionary = entry.get("definition", {})
		var preset_rules: Variant = definition.get("rules", [])
		if preset_rules is Array:
			for rule in preset_rules:
				if rule is Dictionary:
					rules.append(rule.duplicate(true))
	return rules

func _get_selected_resource_path() -> String:
	_ensure_nodes_ready()
	var metadata := _get_selected_resource_metadata()
	if metadata.is_empty():
		return ""
	return String(metadata.get("path", ""))

func _get_selected_resource_metadata() -> Dictionary:
	_ensure_nodes_ready()
	var indices := _resource_list.get_selected_items()
	if indices.is_empty():
		return {}
	var metadata: Dictionary = _resource_list.get_item_metadata(indices[0])
	if metadata == null:
		return {}
	return metadata.duplicate(true)

func _track_default_modulate(control: CanvasItem) -> void:
	_ensure_nodes_ready()
	if control == null:
		return
	_control_default_modulates[control] = control.modulate

func _set_control_highlight(control: CanvasItem, enabled: bool) -> void:
	_ensure_nodes_ready()
	if control == null:
		return
	if enabled:
		control.modulate = _ERROR_TINT
	else:
		var original := _control_default_modulates.get(control, Color(1, 1, 1, 1))
		control.modulate = original

func _get_controller() -> Object:
	_ensure_nodes_ready()
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
	_ensure_nodes_ready()
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
	_ensure_nodes_ready()
	if candidate == null:
		return false
	if candidate is Node:
		return is_instance_valid(candidate)
	return true

func _join_strings(strings: Array[String], delimiter: String) -> String:
	_ensure_nodes_ready()
	if strings.is_empty():
		return ""
	var packed := PackedStringArray()
	for value in strings:
		packed.append(value)
	return delimiter.join(packed)
