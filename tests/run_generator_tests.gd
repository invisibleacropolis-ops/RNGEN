extends SceneTree

const TestSuiteRunner := preload("res://tests/test_suite_runner.gd")

const MANIFEST_PATH := "res://tests/tests_manifest.json"
const GROUP_ID := "generator_core"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var exit_code := await _execute()
    quit(exit_code)

func _execute() -> int:
    var args := _collect_runner_args()
    var runner := TestSuiteRunner.new()
    runner.forward_to_console = true

    var diagnostic_request := TestSuiteRunner.resolve_diagnostic_request(args)
    if diagnostic_request != "":
        var diagnostic_summary: Dictionary = await runner.run_single_diagnostic(diagnostic_request)
        return int(diagnostic_summary.get("exit_code", 1))

    var summary: Dictionary = await runner.run_group(MANIFEST_PATH, GROUP_ID)
    return int(summary.get("exit_code", 1))

func _collect_runner_args() -> PackedStringArray:
    var filtered := PackedStringArray()
    for arg_variant in OS.get_cmdline_args():
        var arg := String(arg_variant)
        if arg == "--quit":
            continue
        filtered.append(arg)
    return filtered
