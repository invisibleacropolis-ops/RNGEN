extends VBoxContainer

## Platform GUI panel that exposes WordlistStrategy configuration controls.
##
## The node is responsible for rendering the metadata-driven form fields,
## exposing a catalogue of available WordListResource assets, and brokering
## preview requests through the RNGProcessor controller. Tool authors can
## drop the scene into any editor hierarchy, assign the controller and
## metadata service paths, and immediately offer seeded previews without
## touching engine singletons from user code.

@export var controller_path: NodePath
@export var metadata_service_path: NodePath

const WordListResource := preload("res://name_generator/resources/WordListResource.gd")

@onready var _resource_list: ItemList = %ResourceList
@onready var _weight_toggle: CheckButton = %UseWeights
@onready var _delimiter_edit: LineEdit = %DelimiterInput
@onready var _seed_edit: LineEdit = %SeedInput
@onready var _preview_button: Button = %PreviewButton
@onready var _preview_label: RichTextLabel = %PreviewOutput
@onready var _validation_label: Label = %ValidationLabel
@onready var _metadata_summary: Label = %MetadataSummary
@onready var _notes_label: Label = %NotesLabel

var _controller_override: Object = null
var _cached_controller: Object = null
var _metadata_service_override: Object = null
var _cached_metadata_service: Object = null
var _resource_catalog_override: Array = []
var _resource_cache: Array = []

func _ready() -> void:
    _preview_button.pressed.connect(_on_preview_button_pressed)
    %RefreshButton.pressed.connect(_on_refresh_pressed)
    _refresh_metadata()
    _refresh_resource_catalog()
    _update_preview_state(null)

func set_controller_override(controller: Object) -> void:
    ## Inject a controller for tests or editor tooling. When provided, the
    ## panel skips all Engine singleton lookups and directs preview requests
    ## to this override instead.
    _controller_override = controller
    _cached_controller = null

func set_metadata_service_override(service: Object) -> void:
    ## Inject a metadata service for deterministic testing. The override takes
    ## precedence over the exported NodePath and Engine singleton lookups.
    _metadata_service_override = service
    _cached_metadata_service = null

func set_resource_catalog_override(entries: Array) -> void:
    ## Provide a deterministic catalogue of WordListResource descriptors. This
    ## is primarily used by automated tests so resource discovery does not walk
    ## the on-disk project layout.
    _resource_catalog_override = entries.duplicate(true)
    _refresh_resource_catalog()

func refresh() -> void:
    ## Public helper that refreshes both strategy metadata and resource listings.
    _refresh_metadata()
    _refresh_resource_catalog()

func get_selected_resource_paths() -> Array:
    ## Return the resource paths for every selected entry in the resource list.
    var paths: Array[String] = []
    for index in _resource_list.get_selected_items():
        var metadata: Dictionary = _resource_list.get_item_metadata(index)
        var path: String = String(metadata.get("path", ""))
        if path != "":
            paths.append(path)
    return paths

func build_config_payload() -> Dictionary:
    ## Construct the middleware configuration dictionary based on the current
    ## form values. Optional fields are omitted when blank to keep the payload
    ## faithful to user intent.
    var config: Dictionary = {
        "strategy": "wordlist",
        "wordlist_paths": get_selected_resource_paths(),
    }
    var delimiter_text := _delimiter_edit.text
    if delimiter_text != "":
        config["delimiter"] = delimiter_text
    config["use_weights"] = _weight_toggle.button_pressed
    var seed_value := _seed_edit.text.strip_edges()
    if seed_value != "":
        config["seed"] = seed_value
    return config

func apply_config_payload(config: Dictionary) -> void:
    var delimiter := String(config.get("delimiter", ""))
    if _delimiter_edit.text != delimiter:
        _delimiter_edit.text = delimiter
    var use_weights := bool(config.get("use_weights", false))
    if _weight_toggle.button_pressed != use_weights:
        _weight_toggle.button_pressed = use_weights
    var seed_value := String(config.get("seed", ""))
    if _seed_edit.text != seed_value:
        _seed_edit.text = seed_value
    var target_paths: Array[String] = []
    var paths_variant := config.get("wordlist_paths", [])
    if paths_variant is Array:
        for entry in paths_variant:
            target_paths.append(String(entry))
    _resource_list.deselect_all()
    if not target_paths.is_empty():
        for index in range(_resource_list.item_count):
            var metadata: Dictionary = _resource_list.get_item_metadata(index)
            if not (metadata is Dictionary):
                continue
            var path := String(metadata.get("path", ""))
            if target_paths.has(path):
                _resource_list.select(index)
    _update_preview_state(null)

func _on_refresh_pressed() -> void:
    refresh()

func _refresh_metadata() -> void:
    var service := _get_metadata_service()
    if service == null:
        _metadata_summary.text = "Wordlist metadata unavailable."
        _notes_label.text = ""
        return

    var required_variant := []
    if service.has_method("get_required_keys"):
        required_variant = service.call("get_required_keys", "wordlist")
    var optional: Dictionary = {}
    if service.has_method("get_optional_key_types"):
        optional = service.call("get_optional_key_types", "wordlist")
    var notes_variant := []
    if service.has_method("get_default_notes"):
        notes_variant = service.call("get_default_notes", "wordlist")

    var required_list: Array[String] = []
    if required_variant is PackedStringArray:
        required_list.assign(required_variant)
    elif required_variant is Array:
        for value in required_variant:
            required_list.append(String(value))

    var summary := []
    if not required_list.is_empty():
        summary.append("Requires: %s" % ", ".join(required_list))
    if optional is Dictionary and not optional.is_empty():
        var optional_strings: Array[String] = []
        for key in optional.keys():
            var variant_type := int(optional[key])
            optional_strings.append("%s (%s)" % [key, Variant.get_type_name(variant_type)])
        optional_strings.sort()
        summary.append("Optional: %s" % ", ".join(optional_strings))
    _metadata_summary.text = " | ".join(summary)

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
        descriptors = _discover_wordlist_resources()

    descriptors.sort_custom(func(a, b):
        var left_name := String(a.get("display_name", a.get("path", "")))
        var right_name := String(b.get("display_name", b.get("path", "")))
        return left_name.nocasecmp_to(right_name) < 0
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
            "has_weights": bool(descriptor.get("has_weights", false)),
        }
        var detail_parts: Array[String] = []
        if metadata["locale"] != "":
            detail_parts.append(metadata["locale"])
        if metadata["domain"] != "":
            detail_parts.append(metadata["domain"])
        var detail_suffix := detail_parts.join(" · ")
        var weight_suffix := ""
        if metadata["has_weights"]:
            weight_suffix = " (Weighted)"
        var line := display_name
        if detail_suffix != "":
            line += " — %s" % detail_suffix
        line += weight_suffix
        var item_index := _resource_list.add_item(line)
        _resource_list.set_item_metadata(item_index, metadata)
        _resource_list.set_item_tooltip(item_index, "%s\nPath: %s" % [line, path])
        _resource_cache.append(metadata)

    if _resource_list.item_count == 0:
        _resource_list.add_item("No WordListResource assets found.")
        _resource_list.set_item_disabled(0, true)

func _discover_wordlist_resources() -> Array:
    ## Recursively scan the data directory for WordListResource assets and
    ## build descriptive entries for the resource browser. The method favours
    ## readability over micro-optimisations because the catalogue is refreshed
    ## only on demand.
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
                if resource == null or not (resource is WordListResource):
                    entry = dir.get_next()
                    continue
                var wordlist: WordListResource = resource
                results.append({
                    "path": resource_path,
                    "display_name": _derive_display_name(resource_path),
                    "locale": wordlist.locale,
                    "domain": wordlist.domain,
                    "has_weights": wordlist.has_weight_data(),
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

func _on_preview_button_pressed() -> void:
    var controller := _get_controller()
    if controller == null:
        _update_preview_state({
            "status": "error",
            "message": "RNGProcessor controller unavailable.",
        })
        return

    var config := build_config_payload()
    if config.get("wordlist_paths", []).is_empty():
        _update_preview_state({
            "status": "error",
            "message": "Select at least one WordListResource to preview output.",
        })
        return

    var response: Variant = controller.call("generate", config)
    if response is Dictionary and response.has("code"):
        var error_dict: Dictionary = response
        var message := String(error_dict.get("message", "Generation failed."))
        _update_preview_state({
            "status": "error",
            "message": message,
            "details": error_dict.get("details", {}),
        })
        return

    var output_text := String(response)
    _update_preview_state({
        "status": "success",
        "message": output_text,
    })

func _update_preview_state(payload: Dictionary) -> void:
    if payload == null:
        _preview_label.visible = false
        _preview_label.text = ""
        _validation_label.visible = false
        _validation_label.text = ""
        return

    var status := String(payload.get("status", ""))
    var message := String(payload.get("message", ""))
    if status == "success":
        _preview_label.visible = true
        _preview_label.text = "[b]Preview:[/b]\n%s" % message
        _validation_label.visible = false
        _validation_label.text = ""
    else:
        _preview_label.visible = false
        _preview_label.text = ""
        _validation_label.visible = true
        _validation_label.text = message

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
