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
const _ERROR_COLOR := Color(0.86, 0.23, 0.23)

@onready var _session_label_edit: LineEdit = %SessionLabel
@onready var _ticket_edit: LineEdit = %TicketInput
@onready var _notes_edit: LineEdit = %NotesInput
@onready var _start_button: Button = %StartSessionButton
@onready var _attach_button: Button = %AttachButton
@onready var _detach_button: Button = %DetachButton
@onready var _stop_button: Button = %StopSessionButton
@onready var _status_label: RichTextLabel = %StatusLabel

var _controller_override: Object = null
var _cached_controller: Object = null
var _debug_rng: DebugRNG = null

func _ready() -> void:
    _status_label.bbcode_enabled = true
    _start_button.pressed.connect(_on_start_pressed)
    _attach_button.pressed.connect(_on_attach_pressed)
    _detach_button.pressed.connect(_on_detach_pressed)
    _stop_button.pressed.connect(_on_stop_pressed)
    _update_button_states()

func set_controller_override(controller: Object) -> void:
    ## Inject a deterministic controller override for tests and tooling.
    _controller_override = controller
    _cached_controller = null
    _update_button_states()

func clear_controller_override() -> void:
    ## Clear the controller override and fall back to exported lookups.
    _controller_override = null
    _cached_controller = null
    _update_button_states()

func get_active_debug_rng() -> DebugRNG:
    ## Return the DebugRNG instance managed by the toolbar, if any.
    return _debug_rng

func refresh() -> void:
    ## External hook to refresh controller lookups and button states.
    _cached_controller = null
    _update_button_states()

func _on_start_pressed() -> void:
    _start_new_session()
    _update_button_states()

func _on_attach_pressed() -> void:
    if _debug_rng == null:
        _set_status(_format_error("Start a DebugRNG session before attaching."))
        return
    var controller := _get_controller()
    if controller == null or not controller.has_method("set_debug_rng"):
        _set_status(_format_error("RNGProcessor controller unavailable; attach skipped."))
        return
    controller.call("set_debug_rng", _debug_rng, true)
    _set_status("Attached DebugRNG helper to middleware.")

func _on_detach_pressed() -> void:
    var detached := _detach_helper()
    if detached:
        _set_status("Detached DebugRNG helper.")
    _update_button_states()

func _on_stop_pressed() -> void:
    _detach_helper(false)
    if _debug_rng != null:
        _debug_rng.close()
        _debug_rng = null
    _set_status("DebugRNG session closed.")
    _update_button_states()

func _start_new_session() -> void:
    if _debug_rng != null:
        _debug_rng.close()
    _debug_rng = DebugRNG.new()
    var metadata := _collect_metadata()
    if _debug_rng.has_method("begin_session"):
        _debug_rng.begin_session(metadata)
    _set_status("DebugRNG session started.")

func _collect_metadata() -> Dictionary:
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
    var controller := _get_controller()
    if controller == null or not controller.has_method("set_debug_rng"):
        if update_status:
            _set_status(_format_error("RNGProcessor controller unavailable; detach skipped."))
        return false
    controller.call("set_debug_rng", null)
    return true

func _update_button_states() -> void:
    var has_debug := _debug_rng != null
    _attach_button.disabled = not has_debug or _get_controller() == null
    _detach_button.disabled = _get_controller() == null
    _stop_button.disabled = not has_debug

func _set_status(message: String) -> void:
    _status_label.text = message

func _format_error(message: String) -> String:
    return "[color=%s]%s[/color]" % [_ERROR_COLOR.to_html(), message]

func _get_controller() -> Object:
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
