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
    var baseline_summary := controller._build_group_summary()
    var baseline_groups := baseline_summary.get("group_summaries", [])
    if baseline_groups is Array:
        baseline_groups = (baseline_groups as Array).duplicate(true)
    else:
        baseline_groups = []
    controller.history = [{
        "run_id": "previous",
        "label": "Previous run",
        "mode": "manifest_groups",
        "exit_code": 0,
        "log_path": "user://qa_runs/previous.log",
        "requested_at": 0,
        "completed_at": 0,
        "aggregate_total": baseline_summary.get("aggregate_total", 0),
        "aggregate_passed": baseline_summary.get("aggregate_passed", 0),
        "aggregate_failed": baseline_summary.get("aggregate_failed", 0),
        "suite_total": baseline_summary.get("suite_total", 0),
        "suite_passed": baseline_summary.get("suite_passed", 0),
        "suite_failed": baseline_summary.get("suite_failed", 0),
        "diagnostic_total": baseline_summary.get("diagnostic_total", 0),
        "diagnostic_passed": baseline_summary.get("diagnostic_passed", 0),
        "diagnostic_failed": baseline_summary.get("diagnostic_failed", 0),
        "overall_success": baseline_summary.get("overall_success", true),
        "group_summaries": baseline_groups,
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

    if panel._log_lines.size() != controller.total_group_log_lines():
        return "Panel should append each emitted log line."
    if panel._status_label.bbcode_text.find("successfully") == -1:
        return "Status label should report successful completion."
    if panel._status_label.bbcode_text.find("Generator core") == -1:
        return "Status label should include a group breakdown."
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
    var group_payloads := [
        {
            "id": "generator_core",
            "label": "Generator core suites",
            "logs": PackedStringArray([
                "Running suite: Generator core stub",
                "Suite summary: 2 passed, 0 failed, 2 total.",
                "ALL TESTS PASSED",
            ]),
            "summary": {
                "exit_code": 0,
                "aggregate_total": 2,
                "aggregate_passed": 2,
                "aggregate_failed": 0,
                "suite_total": 2,
                "suite_passed": 2,
                "suite_failed": 0,
                "diagnostic_total": 0,
                "diagnostic_passed": 0,
                "diagnostic_failed": 0,
                "overall_success": true,
                "failure_summaries": [],
            },
        },
        {
            "id": "platform_gui",
            "label": "Platform GUI suites",
            "logs": PackedStringArray([
                "Running suite: Platform GUI stub",
                "Suite summary: 1 passed, 0 failed, 1 total.",
                "ALL TESTS PASSED",
            ]),
            "summary": {
                "exit_code": 0,
                "aggregate_total": 1,
                "aggregate_passed": 1,
                "aggregate_failed": 0,
                "suite_total": 1,
                "suite_passed": 1,
                "suite_failed": 0,
                "diagnostic_total": 0,
                "diagnostic_passed": 0,
                "diagnostic_failed": 0,
                "overall_success": true,
                "failure_summaries": [],
            },
        },
        {
            "id": "diagnostics",
            "label": "Diagnostics",
            "logs": PackedStringArray([
                "Running diagnostic: Stub diagnostic",
                "Diagnostic summary: 1 passed, 0 failed, 1 total.",
                "ALL TESTS PASSED",
            ]),
            "summary": {
                "exit_code": 0,
                "aggregate_total": 1,
                "aggregate_passed": 1,
                "aggregate_failed": 0,
                "suite_total": 0,
                "suite_passed": 0,
                "suite_failed": 0,
                "diagnostic_total": 1,
                "diagnostic_passed": 1,
                "diagnostic_failed": 0,
                "overall_success": true,
                "failure_summaries": [],
            },
        },
    ]

    func total_group_log_lines() -> int:
        var count := 0
        for payload in group_payloads:
            var logs: Variant = payload.get("logs", PackedStringArray())
            if logs is PackedStringArray:
                count += logs.size()
            elif logs is Array:
                count += logs.size()
        return count

    func get_available_qa_diagnostics() -> Array:
        return diagnostics.duplicate(true)

    func get_recent_qa_runs() -> Array:
        return history.duplicate(true)

    func run_full_test_suite() -> String:
        var run_id := "run_%d" % Time.get_ticks_msec()
        var request := {
            "label": "Stub suite",
            "mode": "manifest_groups",
            "requested_at": Time.get_ticks_msec(),
            "groups": _build_group_descriptors(),
        }
        emit_signal("qa_run_started", run_id, request)
        var aggregated := _build_group_summary()
        for payload in group_payloads:
            var logs: Variant = payload.get("logs", PackedStringArray())
            if logs is PackedStringArray:
                for line in logs:
                    emit_signal("qa_run_output", run_id, line)
            elif logs is Array:
                for line in logs:
                    emit_signal("qa_run_output", run_id, String(line))
        var record := aggregated.duplicate(true)
        if record.has("logs"):
            record.erase("logs")
        record["run_id"] = run_id
        record["label"] = request.get("label", "Stub suite")
        record["mode"] = String(request.get("mode", "manifest_groups"))
        record["log_path"] = "user://qa_runs/%s.log" % run_id
        record["requested_at"] = request.get("requested_at", 0)
        record["completed_at"] = Time.get_ticks_msec()
        history.insert(0, record)
        var payload := {
            "log_path": record.get("log_path", ""),
            "logs": aggregated.get("logs", PackedStringArray()),
            "result": record.duplicate(true),
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

    func _build_group_descriptors() -> Array:
        var descriptors: Array = []
        for payload in group_payloads:
            descriptors.append({
                "id": payload.get("id", ""),
                "label": payload.get("label", ""),
            })
        return descriptors

    func _build_group_summary() -> Dictionary:
        var aggregated := {
            "aggregate_total": 0,
            "aggregate_passed": 0,
            "aggregate_failed": 0,
            "suite_total": 0,
            "suite_passed": 0,
            "suite_failed": 0,
            "diagnostic_total": 0,
            "diagnostic_passed": 0,
            "diagnostic_failed": 0,
            "overall_success": true,
            "failure_summaries": [],
            "exit_code": 0,
            "group_summaries": [],
            "groups": _build_group_descriptors(),
        }
        var combined_logs := PackedStringArray()
        for payload in group_payloads:
            var summary: Dictionary = payload.get("summary", {})
            aggregated["aggregate_total"] += int(summary.get("aggregate_total", 0))
            aggregated["aggregate_passed"] += int(summary.get("aggregate_passed", 0))
            aggregated["aggregate_failed"] += int(summary.get("aggregate_failed", 0))
            aggregated["suite_total"] += int(summary.get("suite_total", 0))
            aggregated["suite_passed"] += int(summary.get("suite_passed", 0))
            aggregated["suite_failed"] += int(summary.get("suite_failed", 0))
            aggregated["diagnostic_total"] += int(summary.get("diagnostic_total", 0))
            aggregated["diagnostic_passed"] += int(summary.get("diagnostic_passed", 0))
            aggregated["diagnostic_failed"] += int(summary.get("diagnostic_failed", 0))
            if int(summary.get("exit_code", 0)) != 0:
                aggregated["exit_code"] = max(aggregated.get("exit_code", 0), int(summary.get("exit_code", 0)))
                aggregated["overall_success"] = false
            var group_entry := summary.duplicate(true)
            group_entry["group_id"] = payload.get("id", "")
            group_entry["group_label"] = payload.get("label", "")
            aggregated["group_summaries"].append(group_entry)
            var logs: Variant = payload.get("logs", PackedStringArray())
            if logs is PackedStringArray:
                combined_logs.append_array(logs)
            elif logs is Array:
                for line in logs:
                    combined_logs.append(String(line))
        aggregated["logs"] = combined_logs
        return aggregated
