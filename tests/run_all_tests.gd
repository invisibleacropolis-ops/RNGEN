extends SceneTree

const MANIFEST_PATH := "res://tests/tests_manifest.json"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var exit_code := _execute()
    quit(exit_code)

func _execute() -> int:
    if not FileAccess.file_exists(MANIFEST_PATH):
        push_error("Test manifest not found at %s" % MANIFEST_PATH)
        return 1

    var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
    if file == null:
        push_error("Unable to open test manifest at %s" % MANIFEST_PATH)
        return 1

    var text := file.get_as_text()
    var json := JSON.new()
    var parse_error := json.parse(text)
    if parse_error != OK:
        push_error("Failed to parse test manifest JSON: %s" % json.get_error_message())
        return 1

    var manifest := json.data
    if manifest == null or not (manifest is Dictionary):
        push_error("Test manifest must be a dictionary with a 'suites' array.")
        return 1

    var suites := manifest.get("suites", [])
    if suites.is_empty():
        push_warning("No test suites declared in manifest. Nothing to run.")
        return 0

    var overall_success := true
    var aggregate_total := 0
    var aggregate_passed := 0
    var aggregate_failed := 0

    for entry in suites:
        var suite_info := entry if entry is Dictionary else {}
        var suite_name := suite_info.get("name", "Unnamed Suite")
        var suite_path := suite_info.get("path", "")

        print("Running suite: %s" % suite_name)

        if suite_path == "":
            overall_success = false
            print("  ✗ Suite path missing from manifest entry.")
            continue

        var script := load(suite_path)
        if script == null:
            overall_success = false
            print("  ✗ Unable to load suite script at %s" % suite_path)
            continue

        var suite_instance = script.new()
        if suite_instance == null or not suite_instance.has_method("run"):
            overall_success = false
            print("  ✗ Suite script %s must implement a `run()` method." % suite_path)
            continue

        var suite_result = suite_instance.run()
        var total := 0
        var passed := 0
        var failed := 0
        var failures := []

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
                var failure_info := failure if failure is Dictionary else {}
                var test_name := failure_info.get("name", "Unnamed Test")
                var message := failure_info.get("message", "")
                print("    ✗ %s -- %s" % [test_name, message])
        else:
            print("  ✅ All tests passed in suite: %s" % suite_name)

    print("\nTest summary: %d passed, %d failed, %d total." % [aggregate_passed, aggregate_failed, aggregate_total])

    if overall_success:
        print("ALL TESTS PASSED")
        return 0

    print("TESTS FAILED")
    return 1
