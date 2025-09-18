extends SceneTree

# Diagnostic Runner
# ------------------
# Invoked with: `godot --headless --script res://tests/run_script_diagnostic.gd --diagnostic-id <diagnostic_id>`
# Alternate flags: `--diagnostic-id=<diagnostic_id>` or environment variable `RNGEN_DIAGNOSTIC_ID=<diagnostic_id>`.
#
# The runner loads `res://tests/script_diagnostics_manifest.json`, which must expose a
# `"diagnostics"` dictionary mapping stable diagnostic IDs to concrete script paths
# (e.g. `"manifest_self_check": "res://tests/diagnostics/manifest_self_check_diagnostic.gd"`).
# Each diagnostic script is expected to export a `run()` function returning a
# dictionary compatible with the test manifest harness:
#
# {
#   "name": "Human-readable diagnostic name",      # optional, used for logs
#   "total": <int>,                                 # number of checks performed
#   "passed": <int>,                                # number of passing checks
#   "failed": <int>,                                # number of failing checks
#   "failures": [                                   # optional array of dictionaries
#     { "name": "check identifier", "message": "context" }
#   ]
# }
#
# Tool authors can add diagnostics by registering a new entry in the manifest and
# implementing the `run()` routine for their script. The runner validates manifest
# structure, surfaces missing or unknown IDs, and propagates the diagnostic's exit
# status (0 for success, 1 for failures or errors).

const MANIFEST_PATH := "res://tests/script_diagnostics_manifest.json"
const DIAGNOSTIC_COLLECTION_KEY := "diagnostics"
const DIAGNOSTIC_ENV_VAR := "RNGEN_DIAGNOSTIC_ID"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var diagnostic_id: String = resolve_diagnostic_request(OS.get_cmdline_args())
    if diagnostic_id == "":
        push_error("No diagnostic ID provided. Pass --diagnostic-id <id> or set %s." % DIAGNOSTIC_ENV_VAR)
        _print_available_diagnostics()
        quit(1)
        return

    var result: Variant = run_diagnostic(diagnostic_id)
    var exit_code: int = _extract_exit_code(result)
    quit(exit_code)

static func resolve_diagnostic_request(args: PackedStringArray) -> String:
    var env_request: String = ""
    if OS.has_environment(DIAGNOSTIC_ENV_VAR):
        env_request = OS.get_environment(DIAGNOSTIC_ENV_VAR).strip_edges()

    var cli_request: String = ""
    var arg_count: int = args.size()
    for index in range(arg_count):
        var arg: String = String(args[index])
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

static func run_diagnostic(diagnostic_id: String) -> Dictionary:
    # Returns a structured result with the diagnostic exit code, totals, and
    # normalized failure entries so callers (including the aggregate runner)
    # can surface consistent summaries.
    if diagnostic_id.strip_edges() == "":
        var message := "Diagnostic ID cannot be empty."
        push_error(message)
        return _build_error_result(diagnostic_id, message)

    var manifest_variant: Variant = _load_manifest()
    if manifest_variant == null:
        return _build_error_result(diagnostic_id, "Unable to load diagnostics manifest.")

    if not (manifest_variant is Dictionary):
        var message := "Diagnostics manifest must be a dictionary."
        push_error(message)
        return _build_error_result(diagnostic_id, message)

    var manifest: Dictionary = manifest_variant

    var diagnostics_variant: Variant = manifest.get(DIAGNOSTIC_COLLECTION_KEY, {})
    if not (diagnostics_variant is Dictionary):
        var message := "Diagnostics manifest must expose a '%s' dictionary." % DIAGNOSTIC_COLLECTION_KEY
        push_error(message)
        return _build_error_result(diagnostic_id, message)

    var diagnostics: Dictionary = diagnostics_variant

    if not diagnostics.has(diagnostic_id):
        var message := "Unknown diagnostic ID '%s'." % diagnostic_id
        push_error(message)
        _print_available_entries(diagnostics)
        return _build_error_result(diagnostic_id, message)

    var script_path: String = String(diagnostics[diagnostic_id])
    if script_path.strip_edges() == "":
        var message := "Manifest entry for '%s' is missing a script path." % diagnostic_id
        push_error(message)
        return _build_error_result(diagnostic_id, message)

    var script: Script = load(script_path) as Script
    if script == null:
        var message := "Unable to load diagnostic script at %s" % script_path
        push_error(message)
        return _build_error_result(diagnostic_id, message)

    var instance: Object = script.new()
    if instance == null or not instance.has_method("run"):
        var message := "Diagnostic %s must implement a `run()` method." % script_path
        push_error(message)
        return _build_error_result(diagnostic_id, message)

    print("Running diagnostic '%s' (%s)" % [diagnostic_id, script_path])
    var raw_result: Variant = instance.run()

    if not (raw_result is Dictionary):
        var message := "Diagnostic '%s' returned an unexpected result type." % diagnostic_id
        push_error(message)
        return _build_error_result(diagnostic_id, message)

    var diagnostic_name: String = raw_result.get("name", diagnostic_id)
    var total: int = int(raw_result.get("total", 0))
    var passed: int = int(raw_result.get("passed", 0))
    var failed: int = int(raw_result.get("failed", 0))
    var failures_variant: Variant = raw_result.get("failures", [])
    var failures: Array = failures_variant if failures_variant is Array else []

    var normalized_failures: Array = []
    for failure in failures:
        var failure_info: Dictionary = failure if failure is Dictionary else {}
        normalized_failures.append({
            "name": failure_info.get("name", "Unnamed Check"),
            "message": failure_info.get("message", "")
        })

    print("  Name: %s" % diagnostic_name)
    print("  Total: %d" % total)
    print("  Passed: %d" % passed)
    print("  Failed: %d" % failed)

    var exit_code: int = 0
    if not normalized_failures.is_empty():
        exit_code = 1
        for failure in normalized_failures:
            var test_name: String = failure.get("name", "Unnamed Check")
            var message: String = failure.get("message", "")
            print("    ✗ %s -- %s" % [test_name, message])
    elif failed > 0:
        exit_code = 1
        var missing_detail_message := "Diagnostic '%s' reported failures without failure details." % diagnostic_id
        normalized_failures.append({
            "name": diagnostic_name,
            "message": missing_detail_message
        })
        print("  ✗ %s" % missing_detail_message)
    elif failed == 0:
        print("  ✅ Diagnostic passed: %s" % diagnostic_name)

    if exit_code == 0:
        print("DIAGNOSTIC PASSED")
    else:
        print("DIAGNOSTIC FAILED")

    return {
        "exit_code": exit_code,
        "id": diagnostic_id,
        "name": diagnostic_name,
        "total": total,
        "passed": passed,
        "failed": failed,
        "failures": normalized_failures.duplicate(true)
    }

static func _extract_exit_code(result: Variant) -> int:
    if result is Dictionary:
        return int(result.get("exit_code", 1))
    return int(result)

static func _build_error_result(diagnostic_id: String, message: String) -> Dictionary:
    var diagnostic_name := diagnostic_id if diagnostic_id != "" else "Diagnostic"
    return {
        "exit_code": 1,
        "id": diagnostic_id,
        "name": diagnostic_name,
        "total": 0,
        "passed": 0,
        "failed": 0,
        "failures": [{
            "name": diagnostic_name,
            "message": message
        }]
    }

static func _load_manifest():
    if not FileAccess.file_exists(MANIFEST_PATH):
        push_error("Diagnostics manifest not found at %s" % MANIFEST_PATH)
        return null

    var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
    if file == null:
        push_error("Unable to open diagnostics manifest at %s" % MANIFEST_PATH)
        return null

    var text: String = file.get_as_text()
    var json: JSON = JSON.new()
    var parse_error: Error = json.parse(text)
    if parse_error != OK:
        push_error("Failed to parse diagnostics manifest JSON: %s" % json.get_error_message())
        return null

    var manifest: Variant = json.data
    if manifest == null or not (manifest is Dictionary):
        push_error("Diagnostics manifest must be a dictionary.")
        return null

    return manifest

static func _print_available_diagnostics() -> void:
    var manifest: Variant = _load_manifest()
    if manifest == null:
        return
    if not (manifest is Dictionary):
        push_error("Diagnostics manifest must be a dictionary.")
        return

    var diagnostics_variant: Variant = manifest.get(DIAGNOSTIC_COLLECTION_KEY, {})
    if not (diagnostics_variant is Dictionary) or diagnostics_variant.is_empty():
        print("No diagnostics are registered in the manifest.")
        return
    var diagnostics: Dictionary = diagnostics_variant
    _print_available_entries(diagnostics)

static func _print_available_entries(diagnostics: Dictionary) -> void:
    print("Available diagnostics:")
    for key in diagnostics.keys():
        print("  - %s" % key)
