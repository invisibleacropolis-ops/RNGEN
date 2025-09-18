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

    var exit_code: int = run_diagnostic(diagnostic_id)
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

static func run_diagnostic(diagnostic_id: String) -> int:
    if diagnostic_id.strip_edges() == "":
        push_error("Diagnostic ID cannot be empty.")
        return 1

    var manifest_variant: Variant = _load_manifest()
    if manifest_variant == null:
        return 1

    if not (manifest_variant is Dictionary):
        push_error("Diagnostics manifest must be a dictionary.")
        return 1

    var manifest: Dictionary = manifest_variant

    var diagnostics_variant: Variant = manifest.get(DIAGNOSTIC_COLLECTION_KEY, {})
    if not (diagnostics_variant is Dictionary):
        push_error("Diagnostics manifest must expose a '%s' dictionary." % DIAGNOSTIC_COLLECTION_KEY)
        return 1

    var diagnostics: Dictionary = diagnostics_variant

    if not diagnostics.has(diagnostic_id):
        push_error("Unknown diagnostic ID '%s'." % diagnostic_id)
        _print_available_entries(diagnostics)
        return 1

    var script_path: String = String(diagnostics[diagnostic_id])
    if script_path.strip_edges() == "":
        push_error("Manifest entry for '%s' is missing a script path." % diagnostic_id)
        return 1

    var script: Script = load(script_path) as Script
    if script == null:
        push_error("Unable to load diagnostic script at %s" % script_path)
        return 1

    var instance: Object = script.new()
    if instance == null or not instance.has_method("run"):
        push_error("Diagnostic %s must implement a `run()` method." % script_path)
        return 1

    print("Running diagnostic '%s' (%s)" % [diagnostic_id, script_path])
    var result: Variant = instance.run()

    if not (result is Dictionary):
        push_error("Diagnostic '%s' returned an unexpected result type." % diagnostic_id)
        return 1

    var diagnostic_name: String = result.get("name", diagnostic_id)
    var total: int = int(result.get("total", 0))
    var passed: int = int(result.get("passed", 0))
    var failed: int = int(result.get("failed", 0))
    var failures_variant: Variant = result.get("failures", [])
    var failures: Array = failures_variant if failures_variant is Array else []

    print("  Name: %s" % diagnostic_name)
    print("  Total: %d" % total)
    print("  Passed: %d" % passed)
    print("  Failed: %d" % failed)

    var exit_code: int = 0
    if not failures.is_empty():
        exit_code = 1
        for failure in failures:
            var failure_info: Dictionary = failure if failure is Dictionary else {}
            var test_name: String = failure_info.get("name", "Unnamed Check")
            var message: String = failure_info.get("message", "")
            print("    ✗ %s -- %s" % [test_name, message])
    elif failed > 0:
        exit_code = 1
        print("  ✗ Diagnostic '%s' reported failures without failure details." % diagnostic_id)
    elif failed == 0:
        print("  ✅ Diagnostic passed: %s" % diagnostic_name)

    if exit_code == 0 and failed > 0:
        exit_code = 1

    if exit_code == 0:
        print("DIAGNOSTIC PASSED")
    else:
        print("DIAGNOSTIC FAILED")

    return exit_code

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
