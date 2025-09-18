extends VBoxContainer

## Platform GUI panel that surfaces deterministic seed state managed by
## RNGProcessor. The dashboard exposes master seed controls, derived stream
## listings, routing visualisations, and import/export helpers so support
## engineers can replay scenarios across machines.

@export var controller_path: NodePath

signal seed_applied(new_seed: int)

const _ERROR_COLOR := Color(1.0, 0.2, 0.2)
const _INFO_COLOR := Color(0.3, 0.6, 0.9)

@onready var _master_seed_label: Label = %MasterSeedLabel
@onready var _seed_input: LineEdit = %SeedInput
@onready var _apply_button: Button = %ApplySeedButton
@onready var _randomize_button: Button = %RandomizeButton
@onready var _refresh_button: Button = %RefreshButton
@onready var _status_label: RichTextLabel = %StatusLabel
@onready var _streams_tree: Tree = %StreamsTree
@onready var _routing_tree: Tree = %RoutingTree
@onready var _export_text: TextEdit = %ExportText
@onready var _export_button: Button = %ExportButton
@onready var _import_button: Button = %ImportButton
@onready var _import_status: Label = %ImportStatus

var _controller_override: Object = null
var _cached_controller: Object = null

func _ready() -> void:
    _status_label.bbcode_enabled = true
    _apply_button.pressed.connect(_on_apply_pressed)
    _randomize_button.pressed.connect(_on_randomize_pressed)
    _refresh_button.pressed.connect(_refresh_dashboard)
    _export_button.pressed.connect(_on_export_pressed)
    _import_button.pressed.connect(_on_import_pressed)
    _seed_input.text_submitted.connect(_on_seed_submitted)
    _streams_tree.set_column_titles_visible(true)
    _streams_tree.set_column_title(0, "Stream")
    _streams_tree.set_column_title(1, "Seed")
    _streams_tree.set_column_title(2, "State")
    _streams_tree.set_column_title(3, "Source")
    _routing_tree.set_column_titles_visible(true)
    _routing_tree.set_column_title(0, "Stream")
    _routing_tree.set_column_title(1, "Router path")
    _routing_tree.set_column_title(2, "Derived seed")
    _routing_tree.set_column_title(3, "Resolved seed")
    _refresh_dashboard()

func refresh() -> void:
    _refresh_dashboard()

func set_controller_override(controller: Object) -> void:
    _controller_override = controller
    _cached_controller = null
    _refresh_dashboard()

func clear_controller_override() -> void:
    _controller_override = null
    _cached_controller = null
    _refresh_dashboard()

func _refresh_dashboard() -> void:
    var controller := _get_controller()
    if controller == null:
        _update_status(_format_error("RNGProcessor controller unavailable."))
        _master_seed_label.text = "--"
        _streams_tree.clear()
        _routing_tree.clear()
        return

    _refresh_master_seed(controller)
    _refresh_streams(controller)
    _refresh_routing(controller)

func _refresh_master_seed(controller: Object) -> void:
    if controller.has_method("get_master_seed"):
        var master_seed := int(controller.call("get_master_seed"))
        _master_seed_label.text = str(master_seed)
        if _seed_input.text.strip_edges() == "":
            _seed_input.text = str(master_seed)
        _update_status("Master seed sourced from middleware.")
    else:
        _master_seed_label.text = "--"
        _update_status(_format_error("Controller missing get_master_seed()."))

func _refresh_streams(controller: Object) -> void:
    _streams_tree.clear()
    var root := _streams_tree.create_item()
    var topology: Dictionary = {}
    if controller.has_method("describe_rng_streams"):
        var payload: Variant = controller.call("describe_rng_streams")
        if payload is Dictionary:
            topology = payload
    var mode := String(topology.get("mode", ""))
    var streams: Dictionary = topology.get("streams", {})
    var stream_names: Array = streams.keys()
    stream_names.sort_custom(func(a, b): return String(a) < String(b))

    for name in stream_names:
        var stream_item := _streams_tree.create_item(root)
        var stream_name := String(name)
        var data: Dictionary = streams.get(stream_name, {})
        stream_item.set_text(0, stream_name)
        stream_item.set_text(1, str(data.get("seed", "")))
        stream_item.set_text(2, str(data.get("state", "")))
        var source := mode if mode != "" else "unknown"
        stream_item.set_text(3, source)
        if data.has("path"):
            stream_item.set_tooltip_text(0, "Router path: %s" % "::".join(data["path"]))
            stream_item.set_tooltip_text(1, stream_item.get_tooltip_text(0))
            stream_item.set_tooltip_text(2, stream_item.get_tooltip_text(0))
        else:
            stream_item.set_tooltip_text(0, "Seed provided by RNGManager.")

    var status_text := "Fallback streams active" if mode == "fallback" else "RNGManager authoritative"
    _import_status.text = status_text

func _refresh_routing(controller: Object) -> void:
    _routing_tree.clear()
    var root := _routing_tree.create_item()
    var routing: Dictionary = {}
    if controller.has_method("describe_stream_routing"):
        var payload: Variant = controller.call("describe_stream_routing")
        if payload is Dictionary:
            routing = payload
    var routes: Array = routing.get("routes", [])
    for route_dict in routes:
        var route := route_dict as Dictionary
        var item := _routing_tree.create_item(root)
        var stream := String(route.get("stream", ""))
        item.set_text(0, stream)
        var path: PackedStringArray = PackedStringArray(route.get("path", PackedStringArray()))
        item.set_text(1, "::".join(path))
        item.set_text(2, str(route.get("derived_seed", "")))
        item.set_text(3, str(route.get("resolved_seed", route.get("derived_seed", ""))))
        if route.has("notes"):
            item.set_tooltip_text(0, String(route["notes"]))
    var notes: Array = routing.get("notes", [])
    if notes.size() > 0:
        var current := _status_label.text
        var error_tag := _ERROR_COLOR.to_html()
        if current == "" or current.find(error_tag) == -1:
            _status_label.text = "[color=%s]%s[/color]" % [_INFO_COLOR.to_html(), String(notes[0])]

func _on_apply_pressed() -> void:
    var seed_text := _seed_input.text.strip_edges()
    if not seed_text.is_valid_int():
        _update_status(_format_error("Seed must be an integer."))
        return
    var controller := _get_controller()
    if controller == null or not controller.has_method("initialize_master_seed"):
        _update_status(_format_error("Controller unavailable; seed not applied."))
        return
    var seed_value := int(seed_text)
    controller.call("initialize_master_seed", seed_value)
    _update_status("Applied master seed %s." % seed_value)
    seed_applied.emit(seed_value)
    _refresh_dashboard()

func _on_randomize_pressed() -> void:
    var controller := _get_controller()
    if controller == null:
        _update_status(_format_error("Controller unavailable; cannot randomize."))
        return
    var seed_value := 0
    if controller.has_method("randomize_master_seed"):
        seed_value = int(controller.call("randomize_master_seed"))
    elif controller.has_method("reset_master_seed"):
        seed_value = int(controller.call("reset_master_seed"))
    _seed_input.text = str(seed_value)
    _update_status("Randomized master seed to %s." % seed_value)
    seed_applied.emit(seed_value)
    _refresh_dashboard()

func _on_seed_submitted(text: String) -> void:
    _seed_input.text = text
    _on_apply_pressed()

func _on_export_pressed() -> void:
    var controller := _get_controller()
    if controller == null or not controller.has_method("export_seed_state"):
        _update_status(_format_error("Controller unavailable; export skipped."))
        return
    var payload: Variant = controller.call("export_seed_state")
    if not (payload is Dictionary):
        _update_status(_format_error("Export failed; middleware returned unexpected payload."))
        return
    var json := JSON.stringify(payload, "  ")
    _export_text.text = json
    _update_status("Exported current seed topology.")

func _on_import_pressed() -> void:
    var controller := _get_controller()
    if controller == null or not controller.has_method("import_seed_state"):
        _update_status(_format_error("Controller unavailable; import skipped."))
        return
    var text := _export_text.text.strip_edges()
    if text == "":
        _update_status(_format_error("Paste a JSON payload before importing."))
        return
    var parser := JSON.new()
    var error := parser.parse(text)
    if error != OK:
        _update_status(_format_error("Invalid JSON: %s." % parser.get_error_message()))
        return
    controller.call("import_seed_state", parser.data)
    _update_status("Imported seed topology.")
    _refresh_dashboard()

func _get_controller() -> Object:
    if _controller_override != null and is_instance_valid(_controller_override):
        return _controller_override
    if _cached_controller != null and is_instance_valid(_cached_controller):
        return _cached_controller
    if controller_path != NodePath("") and has_node(controller_path):
        var node := get_node(controller_path)
        if node != null:
            _cached_controller = node
            return _cached_controller
    if Engine.has_singleton("RNGProcessorController"):
        var singleton := Engine.get_singleton("RNGProcessorController")
        if is_instance_valid(singleton):
            _cached_controller = singleton
            return _cached_controller
    return null

func _update_status(message: String) -> void:
    _status_label.text = message

func _format_error(message: String) -> String:
    return "[color=%s]%s[/color]" % [_ERROR_COLOR.to_html(), message]
