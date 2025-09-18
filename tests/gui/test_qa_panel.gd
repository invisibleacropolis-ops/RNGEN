extends RefCounted

const PANEL_SCENE := preload("res://addons/platform_gui/panels/qa/QAPanel.tscn")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()
    _run_test("populates_catalog_and_history", func(): _test_populates_catalog_and_history())
    _run_test("streams_suite_logs", func(): _test_streams_suite_logs())

    return {
        "suite": "Platform GUI QA Panel",
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

func _test_populates_catalog_and_history() -> Variant:
    var controller := StubQAController.new()
    controller.diagnostics = [{"id": "alpha", "name": "Alpha diagnostic"}]
    controller.history = [{
        "run_id": "previous",
        "label": "Previous run",
        "mode": "manifest",
        "exit_code": 0,
        "log_path": "user://qa_runs/previous.log",
        "requested_at": 0,
        "completed_at": 0,
    }]

    var panel: Control = PANEL_SCENE.instantiate()
    panel.set_controller_override(controller)
    panel._ready()

    if panel._diagnostic_catalog.size() != 1:
        return "Panel should cache diagnostics from the controller."
    var selector := panel.get_node("RunControls/DiagnosticSelector") as OptionButton
    if selector.item_count < 2:
        return "Diagnostic selector should list available diagnostics."
    if panel._history_lookup.size() != 1:
        return "History list should mirror controller entries."
    return null

func _test_streams_suite_logs() -> Variant:
    var controller := StubQAController.new()
    controller.diagnostics = [{"id": "alpha", "name": "Alpha diagnostic"}]

    var panel: Control = PANEL_SCENE.instantiate()
    panel.set_controller_override(controller)
    panel._ready()

    panel._on_run_suite_pressed()

    if panel._log_lines.size() != controller.suite_logs.size():
        return "Panel should append each emitted log line."
    if panel._status_label.bbcode_text.find("successfully") == -1:
        return "Status label should report successful completion."
    if panel._log_path_field.text == "":
        return "Panel should expose the saved log path after completion."
    if panel._open_log_button.disabled:
        return "Open log button should be enabled once a log path is available."
    return null

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

class StubQAController:
    extends Node

    signal qa_run_started(run_id: String, request: Dictionary)
    signal qa_run_output(run_id: String, line: String)
    signal qa_run_completed(run_id: String, payload: Dictionary)

    var diagnostics: Array = []
    var history: Array = []
    var suite_logs := [
        "Running suite: stub",
        "Suite summary: 1 passed, 0 failed, 1 total.",
        "ALL TESTS PASSED",
    ]

    func get_available_qa_diagnostics() -> Array:
        return diagnostics.duplicate(true)

    func get_recent_qa_runs() -> Array:
        return history.duplicate(true)

    func run_full_test_suite() -> String:
        var run_id := "run_%d" % Time.get_ticks_msec()
        var request := {
            "label": "Stub suite",
            "mode": "manifest",
            "requested_at": Time.get_ticks_msec(),
        }
        emit_signal("qa_run_started", run_id, request)
        for line in suite_logs:
            emit_signal("qa_run_output", run_id, line)
        var record := {
            "run_id": run_id,
            "label": request.get("label", "Stub suite"),
            "mode": "manifest",
            "exit_code": 0,
            "log_path": "user://qa_runs/%s.log" % run_id,
            "requested_at": request.get("requested_at", 0),
            "completed_at": Time.get_ticks_msec(),
        }
        history.insert(0, record)
        var payload := {
            "log_path": record.get("log_path", ""),
            "result": {"exit_code": 0},
        }
        emit_signal("qa_run_completed", run_id, payload)
        return run_id

    func run_targeted_diagnostic(diagnostic_id: String) -> String:
        var run_id := "diag_%s" % diagnostic_id
        var request := {
            "label": "Diagnostic %s" % diagnostic_id,
            "mode": "diagnostic",
            "requested_at": Time.get_ticks_msec(),
        }
        emit_signal("qa_run_started", run_id, request)
        emit_signal("qa_run_output", run_id, "Running diagnostic: %s" % diagnostic_id)
        var record := {
            "run_id": run_id,
            "label": request.get("label", "Diagnostic"),
            "mode": "diagnostic",
            "exit_code": 0,
            "log_path": "user://qa_runs/%s.log" % run_id,
            "requested_at": request.get("requested_at", 0),
            "completed_at": Time.get_ticks_msec(),
        }
        history.insert(0, record)
        var payload := {
            "log_path": record.get("log_path", ""),
            "result": {"exit_code": 0},
        }
        emit_signal("qa_run_completed", run_id, payload)
        return run_id
*** End Patch
