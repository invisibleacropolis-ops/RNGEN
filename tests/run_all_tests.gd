extends SceneTree

const TestSuiteRunner := preload("res://tests/test_suite_runner.gd")

const MANIFEST_PATH := "res://tests/tests_manifest.json"
const DIAGNOSTIC_RUNNER_PATH := "res://tests/run_script_diagnostic.gd"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var exit_code := await _execute()
    quit(exit_code)

func _execute() -> int:
    var runner := TestSuiteRunner.new()
    runner.forward_to_console = true
    var args: PackedStringArray = OS.get_cmdline_args()
    var result: Dictionary = await runner.run_from_args(args, MANIFEST_PATH)
    return int(result.get("exit_code", 1))

