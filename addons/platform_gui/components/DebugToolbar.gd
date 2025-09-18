extends HBoxContainer

## Toolbar controls that manage DebugRNG sessions for the Platform GUI.
##
## The toolbar acts as a light-weight front-end to the RNGProcessor
## controller, allowing artists and support engineers to capture session
## metadata, start/stop DebugRNG logging, and toggle helper attachment
## without touching the middleware singletons directly. All controller
## lookups are cached so the component can run in isolation during tests.

@export var controller_path: NodePath

const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")

const _INFO_COLOR := Color(0.3, 0.6, 0.9)
const _WARNING_COLOR := Color(0.82, 0.49, 0.09)
const _ERROR_COLOR := Color(0.86, 0.23, 0.23)

const _STATUS_ICONS := {
    "info": "ℹ️",
    "warning": "⚠️",
    "error": "❌",
}

var _session_label_edit: LineEdit = null
var _ticket_edit: LineEdit = null
var _notes_edit: LineEdit = null
var _start_button: Button = null
var _attach_button: Button = null
var _detach_button: Button = null
var _stop_button: Button = null
var _status_label: RichTextLabel = null

var _controller_override: Object = null
var _cached_controller: Object = null
var _debug_rng: DebugRNG = null


func _ensure_nodes_ready() -> void:
    if _session_label_edit == null:
        _session_label_edit = get_node("SessionLabel") as LineEdit
    if _ticket_edit == null:
        _ticket_edit = get_node("TicketInput") as LineEdit
    if _notes_edit == null:
        _notes_edit = get_node("NotesInput") as LineEdit
    if _start_button == null:
        _start_button = get_node("StartSessionButton") as Button
    if _attach_button == null:
        _attach_button = get_node("AttachButton") as Button
    if _detach_button == null:
        _detach_button = get_node("DetachButton") as Button
    if _stop_button == null:
        _stop_button = get_node("StopSessionButton") as Button
    if _status_label == null:
        _status_label = get_node("StatusLabel") as RichTextLabel

func _ready() -> void:
    _ensure_nodes_ready()
    _status_label.bbcode_enabled = true
    _start_button.pressed.connect(_on_start_pressed)
    _attach_button.pressed.connect(_on_attach_pressed)
    _detach_button.pressed.connect(_on_detach_pressed)
    _stop_button.pressed.connect(_on_stop_pressed)
    _update_button_states()

func set_controller_override(controller: Object) -> void:
    _ensure_nodes_ready()
    ## Inject a deterministic controller override for tests and tooling.
    _controller_override = controller
    _cached_controller = null
    _update_button_states()

func clear_controller_override() -> void:
    _ensure_nodes_ready()
    ## Clear the controller override and fall back to exported lookups.
    _controller_override = null
    _cached_controller = null
    _update_button_states()

func get_active_debug_rng() -> DebugRNG:
    _ensure_nodes_ready()
    ## Return the DebugRNG instance managed by the toolbar, if any.
    return _debug_rng

func refresh() -> void:
    _ensure_nodes_ready()
    ## External hook to refresh controller lookups and button states.
    _cached_controller = null
    _update_button_states()

func _on_start_pressed() -> void:
    _ensure_nodes_ready()
    _start_new_session()
    _update_button_states()

func _on_attach_pressed() -> void:
    _ensure_nodes_ready()
    if _debug_rng == null:
        _set_status("Start a DebugRNG session before attaching.", "error")
        return
    var controller := _get_controller()
    if controller == null or not controller.has_method("set_debug_rng"):
        _set_status("RNGProcessor controller unavailable; attach skipped.", "error")
        return
    controller.call("set_debug_rng", _debug_rng, true)
    _set_status("Attached DebugRNG helper to middleware.")

func _on_detach_pressed() -> void:
    _ensure_nodes_ready()
    var detached := _detach_helper()
    if detached:
        _set_status("Detached DebugRNG helper.")
    _update_button_states()

func _on_stop_pressed() -> void:
    _ensure_nodes_ready()
    _detach_helper(false)
    if _debug_rng != null:
        _debug_rng.close()
        _debug_rng = null
    _set_status("DebugRNG session closed.")
    _update_button_states()

func _start_new_session() -> void:
    _ensure_nodes_ready()
    if _debug_rng != null:
        _debug_rng.close()
    _debug_rng = DebugRNG.new()
    var metadata := _collect_metadata()
    if _debug_rng.has_method("begin_session"):
        _debug_rng.begin_session(metadata)
    _set_status("DebugRNG session started.")

func _collect_metadata() -> Dictionary:
    _ensure_nodes_ready()
    var metadata := {}
    var label := _session_label_edit.text.strip_edges()
    if label != "":
        metadata["label"] = label
    var ticket := _ticket_edit.text.strip_edges()
    if ticket != "":
        metadata["ticket"] = ticket
    var notes := _notes_edit.text.strip_edges()
    if notes != "":
        metadata["notes"] = notes
    return metadata

func _detach_helper(update_status: bool = true) -> bool:
    _ensure_nodes_ready()
    var controller := _get_controller()
    if controller == null or not controller.has_method("set_debug_rng"):
        if update_status:
            _set_status("RNGProcessor controller unavailable; detach skipped.", "error")
        return false
    controller.call("set_debug_rng", null)
    return true

func _update_button_states() -> void:
    _ensure_nodes_ready()
    var has_debug := _debug_rng != null
    _attach_button.disabled = not has_debug or _get_controller() == null
    _detach_button.disabled = _get_controller() == null
    _stop_button.disabled = not has_debug

func _set_status(message: String, severity: String = "info") -> void:
    _ensure_nodes_ready()
    _status_label.bbcode_text = _format_status(message, severity)

func _format_error(message: String) -> String:
    _ensure_nodes_ready()
    return _format_status(message, "error")

func _format_status(message: String, severity: String) -> String:
    _ensure_nodes_ready()
    var color := _INFO_COLOR
    var icon := _STATUS_ICONS.get(severity, _STATUS_ICONS["info"])
    match severity:
        "warning":
            color = _WARNING_COLOR
        "error":
            color = _ERROR_COLOR
    return "[color=%s]%s %s[/color]" % [color.to_html(), icon, message]

func _get_controller() -> Object:
    _ensure_nodes_ready()
    if _controller_override != null:
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
        if singleton != null:
            _cached_controller = singleton
            return _cached_controller
    return null
