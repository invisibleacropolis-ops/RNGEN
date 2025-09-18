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
        return runner_script.call("run_diagnostic", diagnostic_id)

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
    if suites.is_empty():
        push_warning("No test suites declared in manifest. Nothing to run.")
        return 0

    var overall_success := true
    var aggregate_total := 0
    var aggregate_passed := 0
    var aggregate_failed := 0

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
        else:
            print("  ✅ All tests passed in suite: %s" % suite_name)

    print("\nTest summary: %d passed, %d failed, %d total." % [aggregate_passed, aggregate_failed, aggregate_total])

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
