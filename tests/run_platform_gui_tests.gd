extends SceneTree

const TestSuiteRunner := preload("res://tests/test_suite_runner.gd")

const MANIFEST_PATH := "res://tests/tests_manifest.json"
const GROUP_ID := "platform_gui"
const RESULTS_JSON_PATH := "res://tests/results.json"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var summary := await _execute()
    _write_results(summary)
    var exit_code := int(summary.get("exit_code", 1))
    quit(exit_code)

func _execute() -> Dictionary:
    var args := _collect_runner_args()
    var runner := TestSuiteRunner.new()
    runner.forward_to_console = true

    var diagnostic_request := TestSuiteRunner.resolve_diagnostic_request(args)
    if diagnostic_request != "":
        return await runner.run_single_diagnostic(diagnostic_request)

    return await runner.run_group(MANIFEST_PATH, GROUP_ID)

func _collect_runner_args() -> PackedStringArray:
    var filtered := PackedStringArray()
    for arg_variant in OS.get_cmdline_args():
        var arg := String(arg_variant)
        if arg == "--quit":
            continue
        filtered.append(arg)
    return filtered

func _write_results(summary: Dictionary) -> void:
    var json_summary := {
        "scripts_passed": int(summary.get("suite_passed", 0)),
        "scripts_failed": int(summary.get("suite_failed", 0)),
        "assertions": int(summary.get("aggregate_total", 0)),
        "error": null,
    }

    if not bool(summary.get("overall_success", true)):
        var failures := summary.get("failure_summaries", [])
        if failures is Array and not (failures as Array).is_empty():
            var messages: Array = []
            for entry in failures:
                messages.append(String(entry))
            json_summary["error"] = "; ".join(messages)
        else:
            json_summary["error"] = "Test run reported failures."

    var payload := {
        "summary": json_summary,
        "tests": [],
    }

    var file := FileAccess.open(RESULTS_JSON_PATH, FileAccess.WRITE)
    if file == null:
        push_warning("Unable to write manifest results to %s" % RESULTS_JSON_PATH)
        return

    var json_text := JSON.stringify(payload, "  ")
    file.store_string(json_text)
    file.store_string("\n")
    file.close()
