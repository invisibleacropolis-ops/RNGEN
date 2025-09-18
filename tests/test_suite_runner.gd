extends RefCounted

## Helper that runs the aggregated regression suites and diagnostics used by QA tools.
##
## The runner mirrors the behaviour of `tests/run_all_tests.gd` but exposes the
## flow as an async-friendly API so the Platform GUI can execute automated runs
## without spawning an external Godot process. Callers can enable frame yields to
## stream log output into the editor UI while long-running suites execute.

class_name TestSuiteRunner

signal log_emitted(line: String)

const DEFAULT_MANIFEST_PATH := "res://tests/tests_manifest.json"
const DIAGNOSTIC_RUNNER_PATH := "res://tests/run_script_diagnostic.gd"
const SCRIPT_DIAGNOSTIC_MANIFEST_PATH := "res://tests/script_diagnostics_manifest.json"

var forward_to_console: bool = false

var _logs: PackedStringArray = PackedStringArray()
var _yield_callable: Callable = Callable()

func run_from_args(args: PackedStringArray, manifest_path: String = DEFAULT_MANIFEST_PATH, yield_frames: bool = false) -> Dictionary:
    ## Execute the manifest runner while honouring CLI-style diagnostic filters.
    _start_run(yield_frames)
    var diagnostic_request := resolve_diagnostic_request(args)
    var summary: Dictionary
    if diagnostic_request != "":
        summary = await _execute_single_diagnostic(diagnostic_request)
    else:
        summary = await _execute_manifest(manifest_path)
    summary["logs"] = _logs.duplicate()
    return summary

func run_manifest(manifest_path: String = DEFAULT_MANIFEST_PATH, yield_frames: bool = false) -> Dictionary:
    ## Execute the full manifest and return structured summary data.
    _start_run(yield_frames)
    var summary := await _execute_manifest(manifest_path)
    summary["logs"] = _logs.duplicate()
    return summary

func run_single_diagnostic(diagnostic_id: String, yield_frames: bool = false) -> Dictionary:
    ## Execute a specific diagnostic by ID, mirroring the CLI behaviour.
    _start_run(yield_frames)
    var summary := await _execute_single_diagnostic(diagnostic_id)
    summary["logs"] = _logs.duplicate()
    return summary

static func resolve_diagnostic_request(args: PackedStringArray) -> String:
    ## Mirror the CLI flag/environment parsing used by the standalone runner.
    var runner_script := load(DIAGNOSTIC_RUNNER_PATH)
    if runner_script != null and runner_script.has_method("resolve_diagnostic_request"):
        return runner_script.call("resolve_diagnostic_request", args)

    var env_request := ""
    if OS.has_environment("RNGEN_DIAGNOSTIC_ID"):
        env_request = OS.get_environment("RNGEN_DIAGNOSTIC_ID").strip_edges()

    var cli_request := ""
    var arg_count := args.size()
    for index in range(arg_count):
        var arg := String(args[index])
        if arg.begins_with("--diagnostic-id="):
            cli_request = arg.substr("--diagnostic-id=".length()).strip_edges()
        elif arg.begins_with("--diagnostic="):
            cli_request = arg.substr("--diagnostic=".length()).strip_edges()
        elif arg == "--diagnostic-id" or arg == "--diagnostic":
            if index + 1 < arg_count:
                cli_request = String(args[index + 1]).strip_edges()

    if cli_request != "":
        return cli_request

    return env_request

static func list_available_diagnostics() -> Array[Dictionary]:
    ## Build a merged diagnostic index from the manifest and script diagnostics files.
    var catalog: Dictionary = {}

    var script_manifest := _load_json(SCRIPT_DIAGNOSTIC_MANIFEST_PATH)
    if script_manifest is Dictionary:
        var diagnostics_variant := script_manifest.get("diagnostics", {})
        if diagnostics_variant is Dictionary:
            var diagnostics_dict: Dictionary = diagnostics_variant
            for id_key in diagnostics_dict.keys():
                var entry := {
                    "id": String(id_key),
                    "name": String(id_key),
                    "summary": "",
                    "path": String(diagnostics_dict[id_key]),
                    "source": "script_manifest",
                }
                catalog[entry["id"]] = entry

    var manifest := _load_json(DEFAULT_MANIFEST_PATH)
    if manifest is Dictionary:
        var diagnostics_array_variant := manifest.get("diagnostics", [])
        if diagnostics_array_variant is Array:
            for entry_variant in diagnostics_array_variant:
                var info: Dictionary = entry_variant if entry_variant is Dictionary else {}
                var diag_id := String(info.get("id", "")).strip_edges()
                if diag_id == "":
                    continue
                var descriptor := catalog.get(diag_id, {
                    "id": diag_id,
                    "name": diag_id,
                    "summary": "",
                    "path": "",
                    "source": "tests_manifest",
                })
                descriptor["name"] = String(info.get("name", descriptor.get("name", diag_id)))
                descriptor["summary"] = String(info.get("summary", descriptor.get("summary", "")))
                if info.has("path"):
                    descriptor["path"] = String(info.get("path", descriptor.get("path", "")))
                descriptor["source"] = "tests_manifest"
                catalog[diag_id] = descriptor

    var diagnostics: Array[Dictionary] = []
    for entry in catalog.values():
        diagnostics.append(entry)

    diagnostics.sort_custom(func(a, b):
        return String(a.get("name", "")) < String(b.get("name", ""))
    )

    return diagnostics

static func _load_json(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    var text := file.get_as_text()
    var parser := JSON.new()
    if parser.parse(text) != OK:
        return null
    return parser.data

func _start_run(yield_frames: bool) -> void:
    _logs.clear()
    if yield_frames:
        _yield_callable = Callable(self, "_yield_frame")
    else:
        _yield_callable = Callable()

func _duplicate_variant(value: Variant) -> Variant:
    if value is Dictionary:
        return (value as Dictionary).duplicate(true)
    if value is Array:
        return (value as Array).duplicate(true)
    return value

func _make_summary_payload() -> Dictionary:
    return {
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
    }

func _make_failure_summary(label: String, message: String) -> Dictionary:
    return {
        "name": label,
        "message": message,
    }

func _normalize_failures(failures_variant: Variant) -> Array:
    var failures: Array = []
    if failures_variant is Array:
        for failure in failures_variant:
            var failure_info: Dictionary = failure if failure is Dictionary else {}
            failures.append({
                "name": failure_info.get("name", "Unnamed Check"),
                "message": failure_info.get("message", ""),
            })
    return failures

func _is_success(exit_code: int, failures: Array) -> bool:
    if exit_code != 0:
        return false
    return failures.is_empty()

func _summarize_diagnostic_result(result: Dictionary, summary: Dictionary, label: String) -> void:
    var total: int = int(result.get("total", 0))
    var passed: int = int(result.get("passed", 0))
    var failed: int = int(result.get("failed", 0))
    var failures: Array = _normalize_failures(result.get("failures", []))

    summary["aggregate_total"] += total
    summary["aggregate_passed"] += passed
    summary["aggregate_failed"] += failed
    summary["diagnostic_total"] += total
    summary["diagnostic_passed"] += passed
    summary["diagnostic_failed"] += failed

    if failed > 0 or not failures.is_empty():
        summary["overall_success"] = false
        for failure in failures:
            var name := failure.get("name", label)
            var message := failure.get("message", "")
            summary["failure_summaries"].append("Diagnostic %s :: %s -- %s" % [label, name, message])

func _summarize_suite_result(result: Dictionary, suite_name: String, summary: Dictionary) -> void:
    var total: int = int(result.get("total", 0))
    var passed: int = int(result.get("passed", 0))
    var failed: int = int(result.get("failed", 0))
    var failures: Array = _normalize_failures(result.get("failures", []))

    summary["aggregate_total"] += total
    summary["aggregate_passed"] += passed
    summary["aggregate_failed"] += failed
    summary["suite_total"] += total
    summary["suite_passed"] += passed
    summary["suite_failed"] += failed

    if failed > 0 or not failures.is_empty():
        summary["overall_success"] = false
        for failure in failures:
            var name := failure.get("name", "Unnamed Test")
            var message := failure.get("message", "")
            summary["failure_summaries"].append("Suite %s :: %s -- %s" % [suite_name, name, message])

func _build_exit_summary(summary: Dictionary) -> Dictionary:
    var exit_code := 0 if summary.get("overall_success", false) else 1
    summary["exit_code"] = exit_code
    return summary

func _ensure_summary_array(summary: Dictionary, key: String) -> void:
    if not summary.has(key) or not (summary[key] is Array):
        summary[key] = []

func _ensure_summary_numbers(summary: Dictionary) -> void:
    var numeric_keys := [
        "aggregate_total",
        "aggregate_passed",
        "aggregate_failed",
        "suite_total",
        "suite_passed",
        "suite_failed",
        "diagnostic_total",
        "diagnostic_passed",
        "diagnostic_failed",
    ]
    for key in numeric_keys:
        summary[key] = int(summary.get(key, 0))

func _ensure_summary_flags(summary: Dictionary) -> void:
    summary["overall_success"] = bool(summary.get("overall_success", false))

func _finalize_summary(summary: Dictionary) -> Dictionary:
    _ensure_summary_numbers(summary)
    _ensure_summary_array(summary, "failure_summaries")
    _ensure_summary_flags(summary)
    return _build_exit_summary(summary)

func _duplicate_summary(summary: Dictionary) -> Dictionary:
    var payload := {}
    for key in summary.keys():
        payload[key] = _duplicate_variant(summary[key])
    return payload

func _extract_function_state(result: Variant) -> Variant:
    if result is GDScriptFunctionState:
        return await result
    return result

func _execute_single_diagnostic(diagnostic_id: String) -> Dictionary:
    var summary := _make_summary_payload()
    var clean_id := diagnostic_id.strip_edges()
    if clean_id == "":
        await _log("Diagnostic ID cannot be empty.")
        summary["overall_success"] = false
        summary["failure_summaries"].append("Diagnostic :: Missing diagnostic ID")
        return _finalize_summary(summary)

    var runner_script: Resource = load(DIAGNOSTIC_RUNNER_PATH)
    if runner_script == null or not runner_script.has_method("run_diagnostic"):
        await _log("Unable to load diagnostic runner at %s" % DIAGNOSTIC_RUNNER_PATH)
        summary["overall_success"] = false
        summary["failure_summaries"].append("Diagnostic %s :: Diagnostic runner unavailable." % clean_id)
        return _finalize_summary(summary)

    await _log("Single diagnostic requested: %s" % clean_id)
    var raw_result: Variant = runner_script.call("run_diagnostic", clean_id)
    raw_result = await _extract_function_state(raw_result)

    var diagnostic_result: Dictionary = raw_result if raw_result is Dictionary else {}
    var exit_code: int = int(diagnostic_result.get("exit_code", 1))
    var failures: Array = _normalize_failures(diagnostic_result.get("failures", []))

    await _log("Diagnostic name: %s" % diagnostic_result.get("name", clean_id))
    await _log("  Total: %d" % int(diagnostic_result.get("total", 0)))
    await _log("  Passed: %d" % int(diagnostic_result.get("passed", 0)))
    await _log("  Failed: %d" % int(diagnostic_result.get("failed", 0)))

    if not failures.is_empty():
        summary["overall_success"] = false
        for failure in failures:
            await _log("    ✗ %s -- %s" % [failure.get("name", "Unnamed Check"), failure.get("message", "")])
    elif exit_code != 0:
        summary["overall_success"] = false
        await _log("  ✗ Diagnostic reported failures without detail entries.")
    else:
        await _log("  ✅ Diagnostic passed: %s" % diagnostic_result.get("name", clean_id))

    if exit_code == 0 and failures.is_empty():
        await _log("DIAGNOSTIC PASSED")
    else:
        await _log("DIAGNOSTIC FAILED")
        summary["overall_success"] = false

    _summarize_diagnostic_result(diagnostic_result, summary, diagnostic_result.get("name", clean_id))

    return _finalize_summary(summary)

func _execute_manifest(manifest_path: String) -> Dictionary:
    var summary := _make_summary_payload()

    if not FileAccess.file_exists(manifest_path):
        var message := "Test manifest not found at %s" % manifest_path
        push_error(message)
        await _log(message)
        summary["overall_success"] = false
        return _finalize_summary(summary)

    var file := FileAccess.open(manifest_path, FileAccess.READ)
    if file == null:
        var message := "Unable to open test manifest at %s" % manifest_path
        push_error(message)
        await _log(message)
        summary["overall_success"] = false
        return _finalize_summary(summary)

    var text := file.get_as_text()
    var json := JSON.new()
    if json.parse(text) != OK:
        var message := "Failed to parse test manifest JSON: %s" % json.get_error_message()
        push_error(message)
        await _log(message)
        summary["overall_success"] = false
        return _finalize_summary(summary)

    var manifest: Dictionary = json.data if json.data is Dictionary else {}
    var suites: Array = manifest.get("suites", [])
    var diagnostics: Array = manifest.get("diagnostics", [])

    if suites.is_empty() and diagnostics.is_empty():
        await _log("No test suites or diagnostics declared in manifest. Nothing to run.")
        return _finalize_summary(summary)

    for entry in suites:
        var suite_info: Dictionary = entry if entry is Dictionary else {}
        var suite_name := String(suite_info.get("name", "Unnamed Suite"))
        var suite_path := String(suite_info.get("path", ""))

        await _log("Running suite: %s" % suite_name)

        if suite_path == "":
            summary["overall_success"] = false
            await _log("  ✗ Suite path missing from manifest entry.")
            continue

        var script: Script = load(suite_path) as Script
        if script == null:
            summary["overall_success"] = false
            await _log("  ✗ Unable to load suite script at %s" % suite_path)
            continue

        var suite_instance: Object = script.new()
        if suite_instance == null or not suite_instance.has_method("run"):
            summary["overall_success"] = false
            await _log("  ✗ Suite script %s must implement a `run()` method." % suite_path)
            continue

        var suite_result_variant: Variant = suite_instance.run()
        suite_result_variant = await _extract_function_state(suite_result_variant)

        if not (suite_result_variant is Dictionary):
            summary["overall_success"] = false
            await _log("  ✗ Suite %s returned an unexpected result type." % suite_name)
            continue

        var suite_result: Dictionary = suite_result_variant
        _summarize_suite_result(suite_result, suite_name, summary)

        await _log("  Total: %d" % int(suite_result.get("total", 0)))
        await _log("  Passed: %d" % int(suite_result.get("passed", 0)))
        await _log("  Failed: %d" % int(suite_result.get("failed", 0)))

        var failures: Array = _normalize_failures(suite_result.get("failures", []))
        if not failures.is_empty():
            summary["overall_success"] = false
            for failure in failures:
                await _log("    ✗ %s -- %s" % [failure.get("name", "Unnamed Test"), failure.get("message", "")])
        else:
            await _log("  ✅ All tests passed in suite: %s" % suite_name)

    if not diagnostics.is_empty():
        var runner_script: Resource = load(DIAGNOSTIC_RUNNER_PATH)
        if runner_script == null or not runner_script.has_method("run_diagnostic"):
            summary["overall_success"] = false
            var message := "Unable to load diagnostic runner for manifest diagnostics."
            push_error(message)
            await _log(message)
        else:
            for entry_variant in diagnostics:
                var diagnostic_info: Dictionary = entry_variant if entry_variant is Dictionary else {}
                var entry_diagnostic_id := String(diagnostic_info.get("id", "")).strip_edges()
                var diagnostic_name := String(diagnostic_info.get("name", entry_diagnostic_id if entry_diagnostic_id != "" else "Unnamed Diagnostic"))
                var diagnostic_summary := String(diagnostic_info.get("summary", ""))

                await _log("Running diagnostic: %s (%s)" % [diagnostic_name, entry_diagnostic_id])
                if diagnostic_summary != "":
                    await _log("  Summary: %s" % diagnostic_summary)

                if entry_diagnostic_id == "":
                    summary["overall_success"] = false
                    var missing_id_message := "Diagnostic entry is missing an 'id' field."
                    await _log("  ✗ %s" % missing_id_message)
                    summary["failure_summaries"].append("Diagnostic %s :: %s" % [diagnostic_name, missing_id_message])
                    continue

                var diagnostic_result_variant: Variant = runner_script.call("run_diagnostic", entry_diagnostic_id)
                diagnostic_result_variant = await _extract_function_state(diagnostic_result_variant)

                var diagnostic_result: Dictionary = diagnostic_result_variant if diagnostic_result_variant is Dictionary else {}
                var diagnostic_exit_code := int(diagnostic_result.get("exit_code", 1))

                await _log("  Total: %d" % int(diagnostic_result.get("total", 0)))
                await _log("  Passed: %d" % int(diagnostic_result.get("passed", 0)))
                await _log("  Failed: %d" % int(diagnostic_result.get("failed", 0)))

                var failures: Array = _normalize_failures(diagnostic_result.get("failures", []))
                if not failures.is_empty():
                    summary["overall_success"] = false
                    for failure in failures:
                        await _log("    ✗ %s -- %s" % [failure.get("name", "Unnamed Check"), failure.get("message", "")])
                elif diagnostic_exit_code != 0:
                    summary["overall_success"] = false
                    await _log("  ✗ Diagnostic reported failures without detail entries.")

                _summarize_diagnostic_result(diagnostic_result, summary, diagnostic_name)

    await _log("\nSuite summary: %d passed, %d failed, %d total." % [summary.get("suite_passed", 0), summary.get("suite_failed", 0), summary.get("suite_total", 0)])
    await _log("Diagnostic summary: %d passed, %d failed, %d total." % [summary.get("diagnostic_passed", 0), summary.get("diagnostic_failed", 0), summary.get("diagnostic_total", 0)])
    await _log("Overall summary: %d passed, %d failed, %d total." % [summary.get("aggregate_passed", 0), summary.get("aggregate_failed", 0), summary.get("aggregate_total", 0)])

    if not summary.get("failure_summaries", []).is_empty():
        await _log("\nFailure details:")
        for failure_summary in summary.get("failure_summaries", []):
            await _log("  - %s" % failure_summary)

    if summary.get("overall_success", false):
        await _log("ALL TESTS PASSED")
    else:
        await _log("TESTS FAILED")

    return _finalize_summary(summary)

func _log(message: String) -> void:
    _logs.append(message)
    emit_signal("log_emitted", message)
    if forward_to_console:
        print(message)
    if not _yield_callable.is_valid():
        return
    var result := _yield_callable.call()
    if result is GDScriptFunctionState:
        await result

func _yield_frame() -> void:
    var main_loop := Engine.get_main_loop()
    if main_loop is SceneTree:
        await (main_loop as SceneTree).process_frame
