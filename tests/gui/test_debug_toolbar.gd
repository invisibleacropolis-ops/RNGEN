extends RefCounted

const TOOLBAR_SCENE := preload("res://addons/platform_gui/components/DebugToolbar.tscn")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()
    _run_test("starts_session_and_captures_metadata", func(): _test_starts_session_and_captures_metadata())
    _run_test("attaches_and_detaches_helper", func(): _test_attaches_and_detaches_helper())
    _run_test("stop_closes_session_and_detaches", func(): _test_stop_closes_session_and_detaches())

    return {
        "suite": "Platform GUI Debug Toolbar",
        "total": _total,
        "passed": _passed,
        "failed": _failed,
        "failures": _failures.duplicate(true),
    }

func _run_test(name: String, callable: Callable) -> void:
    _total += 1
    var message := callable.call()
    if message == null:
        _passed += 1
        return
    _failed += 1
    _failures.append({"name": name, "message": String(message)})

func _test_starts_session_and_captures_metadata() -> Variant:
    var toolbar: Control = TOOLBAR_SCENE.instantiate()
    toolbar._ready()
    (toolbar.get_node("SessionLabel") as LineEdit).text = "QA Session"
    (toolbar.get_node("TicketInput") as LineEdit).text = "BUG-123"
    (toolbar.get_node("NotesInput") as LineEdit).text = "Repro on macOS"

    toolbar._on_start_pressed()

    var debug_rng := toolbar.get_active_debug_rng()
    if debug_rng == null:
        return "Toolbar should create a DebugRNG instance when starting a session."
    var payload := debug_rng.read_current_log()
    var metadata: Dictionary = payload.get("metadata", {})
    if metadata.get("label", "") != "QA Session":
        return "Session metadata should include the provided label."
    if metadata.get("ticket", "") != "BUG-123":
        return "Session metadata should include the provided ticket identifier."
    if metadata.get("notes", "") != "Repro on macOS":
        return "Session metadata should include the notes field."
    return null

func _test_attaches_and_detaches_helper() -> Variant:
    var toolbar: Control = TOOLBAR_SCENE.instantiate()
    var controller := ControllerStub.new()
    toolbar.set_controller_override(controller)
    toolbar._ready()
    toolbar._on_start_pressed()

    toolbar._on_attach_pressed()
    if controller.attach_calls != 1:
        return "Attach button should forward the DebugRNG instance to the controller."
    if controller.last_debug_rng != toolbar.get_active_debug_rng():
        return "Controller should receive the active DebugRNG instance."

    toolbar._on_detach_pressed()
    if controller.detach_calls != 1:
        return "Detach button should clear the DebugRNG helper through the controller."
    if controller.last_debug_rng != null:
        return "Controller should no longer reference the helper after detaching."
    return null

func _test_stop_closes_session_and_detaches() -> Variant:
    var toolbar: Control = TOOLBAR_SCENE.instantiate()
    var controller := ControllerStub.new()
    toolbar.set_controller_override(controller)
    toolbar._ready()
    toolbar._on_start_pressed()
    var debug_rng := toolbar.get_active_debug_rng()
    toolbar._on_attach_pressed()

    toolbar._on_stop_pressed()

    if toolbar.get_active_debug_rng() != null:
        return "Stop button should dispose of the active DebugRNG instance."
    if controller.detach_calls == 0:
        return "Stop button should detach the helper from the controller."
    if debug_rng.is_session_open():
        return "DebugRNG session should be closed after pressing stop."
    return null

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

class ControllerStub:
    extends Node

    var last_debug_rng: Object = null
    var attach_calls: int = 0
    var detach_calls: int = 0

    func set_debug_rng(debug_rng: Object, attach_to_debug: bool = true) -> void:
        last_debug_rng = debug_rng
        if debug_rng == null:
            detach_calls += 1
        else:
            attach_calls += 1

    func get_debug_rng() -> Object:
        return last_debug_rng
