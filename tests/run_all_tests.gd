extends SceneTree

const MANIFEST_PATH := "res://tests/tests_manifest.json"
const DIAGNOSTIC_RUNNER_PATH := "res://tests/run_script_diagnostic.gd"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var exit_code := _execute()
    quit(exit_code)

func _execute() -> int:
    var args: PackedStringArray = OS.get_cmdline_args()
    var diagnostic_id: String = _resolve_diagnostic_request(args)
    if diagnostic_id != "":
        print("Single diagnostic requested: %s" % diagnostic_id)
        var runner_script: Resource = load(DIAGNOSTIC_RUNNER_PATH)
        if runner_script == null:
            push_error("Unable to load diagnostic runner at %s" % DIAGNOSTIC_RUNNER_PATH)
            return 1
        if not runner_script.has_method("run_diagnostic"):
            push_error("Diagnostic runner script missing required `run_diagnostic()` function.")
            return 1
        var single_result: Variant = runner_script.call("run_diagnostic", diagnostic_id)
        if single_result is Dictionary:
            return int(single_result.get("exit_code", 1))
        return int(single_result)

    if not FileAccess.file_exists(MANIFEST_PATH):
        push_error("Test manifest not found at %s" % MANIFEST_PATH)
        return 1

    var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
    if file == null:
        push_error("Unable to open test manifest at %s" % MANIFEST_PATH)
        return 1

    var text: String = file.get_as_text()
    var json: JSON = JSON.new()
    var parse_error: Error = json.parse(text)
    if parse_error != OK:
        push_error("Failed to parse test manifest JSON: %s" % json.get_error_message())
        return 1

    var manifest: Dictionary = json.data
    if manifest == null or not (manifest is Dictionary):
        push_error("Test manifest must be a dictionary with a 'suites' array.")
        return 1

    var suites: Array = manifest.get("suites", [])
    var diagnostics: Array = manifest.get("diagnostics", [])

    if suites.is_empty() and diagnostics.is_empty():
        push_warning("No test suites or diagnostics declared in manifest. Nothing to run.")
        return 0

    var overall_success := true
    var aggregate_total := 0
    var aggregate_passed := 0
    var aggregate_failed := 0
    var suite_total := 0
    var suite_passed := 0
    var suite_failed := 0
    var diagnostic_total := 0
    var diagnostic_passed := 0
    var diagnostic_failed := 0
    var failure_summaries: Array = []

    for entry in suites:
        var suite_info: Dictionary = entry if entry is Dictionary else {}
        var suite_name: String = suite_info.get("name", "Unnamed Suite")
        var suite_path: String = suite_info.get("path", "")

        print("Running suite: %s" % suite_name)

        if suite_path == "":
            overall_success = false
            print("  ✗ Suite path missing from manifest entry.")
            continue

        var script: Script = load(suite_path) as Script
        if script == null:
            overall_success = false
            print("  ✗ Unable to load suite script at %s" % suite_path)
            continue

        var suite_instance: Object = script.new()
        if suite_instance == null or not suite_instance.has_method("run"):
            overall_success = false
            print("  ✗ Suite script %s must implement a `run()` method." % suite_path)
            continue

        var suite_result: Variant = suite_instance.run()
        var total := 0
        var passed := 0
        var failed := 0
        var failures: Array = []

        if suite_result is Dictionary:
            total = int(suite_result.get("total", 0))
            passed = int(suite_result.get("passed", 0))
            failed = int(suite_result.get("failed", 0))
            failures = suite_result.get("failures", [])
        else:
            overall_success = false
            print("  ✗ Suite %s returned an unexpected result type." % suite_name)
            continue

        aggregate_total += total
        aggregate_passed += passed
        aggregate_failed += failed
        suite_total += total
        suite_passed += passed
        suite_failed += failed

        print("  Total: %d" % total)
        print("  Passed: %d" % passed)
        print("  Failed: %d" % failed)

        if not failures.is_empty():
            overall_success = false
            for failure in failures:
                var failure_info: Dictionary = failure if failure is Dictionary else {}
                var test_name: String = failure_info.get("name", "Unnamed Test")
                var message: String = failure_info.get("message", "")
                print("    ✗ %s -- %s" % [test_name, message])
                failure_summaries.append("Suite %s :: %s -- %s" % [suite_name, test_name, message])
        else:
            print("  ✅ All tests passed in suite: %s" % suite_name)

    if not diagnostics.is_empty():
        var runner_script: Resource = load(DIAGNOSTIC_RUNNER_PATH)
        if runner_script == null or not runner_script.has_method("run_diagnostic"):
            overall_success = false
            push_error("Unable to load diagnostic runner for manifest diagnostics.")
        else:
            for entry in diagnostics:
                var diagnostic_info: Dictionary = entry if entry is Dictionary else {}
                var entry_diagnostic_id: String = diagnostic_info.get("id", "").strip_edges()
                var diagnostic_name: String = diagnostic_info.get("name", entry_diagnostic_id if entry_diagnostic_id != "" else "Unnamed Diagnostic")
                var diagnostic_summary: String = diagnostic_info.get("summary", "")

                print("Running diagnostic: %s (%s)" % [diagnostic_name, entry_diagnostic_id])
                if diagnostic_summary != "":
                    print("  Summary: %s" % diagnostic_summary)

                if entry_diagnostic_id == "":
                    overall_success = false
                    var missing_id_message := "Diagnostic entry is missing an 'id' field."
                    print("  ✗ %s" % missing_id_message)
                    failure_summaries.append("Diagnostic %s :: %s" % [diagnostic_name, missing_id_message])
                    continue

                var diagnostic_result_variant: Variant = runner_script.call("run_diagnostic", entry_diagnostic_id)
                var diagnostic_result: Dictionary = {}
                var diagnostic_exit_code := 1

                if diagnostic_result_variant is Dictionary:
                    diagnostic_result = diagnostic_result_variant
                    diagnostic_exit_code = int(diagnostic_result.get("exit_code", 1))
                else:
                    diagnostic_exit_code = int(diagnostic_result_variant)

                var total: int = int(diagnostic_result.get("total", 0))
                var passed: int = int(diagnostic_result.get("passed", 0))
                var failed: int = int(diagnostic_result.get("failed", 0))
                var failures_variant: Variant = diagnostic_result.get("failures", [])
                var failures: Array = failures_variant if failures_variant is Array else []

                aggregate_total += total
                aggregate_passed += passed
                aggregate_failed += failed
                diagnostic_total += total
                diagnostic_passed += passed
                diagnostic_failed += failed

                if diagnostic_exit_code != 0:
                    overall_success = false

                if not failures.is_empty():
                    for failure in failures:
                        var failure_info: Dictionary = failure if failure is Dictionary else {}
                        var test_name: String = failure_info.get("name", "Unnamed Check")
                        var message: String = failure_info.get("message", "")
                        failure_summaries.append("Diagnostic %s :: %s -- %s" % [diagnostic_name, test_name, message])
                elif diagnostic_exit_code != 0:
                    failure_summaries.append("Diagnostic %s :: Reported failures without details." % diagnostic_name)

    print("\nSuite summary: %d passed, %d failed, %d total." % [suite_passed, suite_failed, suite_total])
    print("Diagnostic summary: %d passed, %d failed, %d total." % [diagnostic_passed, diagnostic_failed, diagnostic_total])
    print("Overall summary: %d passed, %d failed, %d total." % [aggregate_passed, aggregate_failed, aggregate_total])

    if not failure_summaries.is_empty():
        print("\nFailure details:")
        for failure_summary in failure_summaries:
            print("  - %s" % failure_summary)

    if overall_success:
        print("ALL TESTS PASSED")
        return 0

    print("TESTS FAILED")
    return 1

func _resolve_diagnostic_request(args: PackedStringArray) -> String:
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
