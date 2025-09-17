extends RefCounted

const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")
const RNGProcessor := preload("res://name_generator/RNGProcessor.gd")

const WORDLIST_PATH := "res://tests/test_assets/wordlist_basic.tres"

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("report_includes_generation_events", func(): _test_report_includes_generation_events())

    return {
        "suite": "Debug RNG",
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
    _failures.append({
        "name": name,
        "message": String(message),
    })

func _test_report_includes_generation_events() -> Variant:
    var processor := _make_processor()
    var debug_rng := DebugRNG.new()
    var log_path := "user://debug_rng_report_test.txt"
    _remove_file(log_path)

    debug_rng.begin_session({
        "test": "report_includes_generation_events",
    })
    debug_rng.attach_to_processor(processor, log_path)

    processor.initialize_master_seed(10101)

    debug_rng.record_warning("pre-flight warning", {"stage": "setup"})

    var success_config := {
        "strategy": "wordlist",
        "wordlist_paths": [WORDLIST_PATH],
        "seed": "debug_rng_success",
    }

    var success := processor.generate(success_config)
    if success is Dictionary and success.get("code", "") != "":
        return "Expected successful configuration to produce a generated value."

    var failure_config := {
        "strategy": "wordlist",
        "wordlist_paths": [],
        "seed": "debug_rng_failure",
    }

    var failure := processor.generate(failure_config)
    if not (failure is Dictionary) or failure.get("code", "") == "":
        return "Expected failure configuration to surface an error dictionary."

    debug_rng.record_warning("post-failure note", {"stage": "teardown"})

    debug_rng.close()

    var file := FileAccess.open(log_path, FileAccess.READ)
    if file == null:
        return "DebugRNG must write the report to disk on close."

    var report := file.get_as_text()
    if report.find("Session Metadata") == -1:
        return "Report should include a Session Metadata section."

    if report.find("Generation Timeline") == -1:
        return "Report should include a Generation Timeline section."

    var start_index := report.find("START")
    var complete_index := report.find("COMPLETE")
    var fail_index := report.find("FAIL")
    if start_index == -1 or complete_index == -1 or fail_index == -1:
        return "Timeline must document start, completion, and failure events."

    if not (start_index < complete_index and complete_index < fail_index):
        return "Timeline entries should appear in chronological order."

    if report.find("STRATEGY_ERROR") == -1:
        return "Strategy errors should be captured in the timeline."

    if report.find("pre-flight warning") == -1 or report.find("post-failure note") == -1:
        return "Warnings section must include recorded diagnostics."

    if report.find("Stream Usage") == -1:
        return "Report should contain a Stream Usage section."

    if report.find("wordlist::debug_rng_success") == -1:
        return "Stream usage must document derived RNG streams."

    if report.find("Total Calls: 2") == -1:
        return "Aggregate stats should report the total number of invocations."

    if report.find("Successful Calls: 1") == -1:
        return "Aggregate stats should track successful requests."

    if report.find("Failed Calls: 1") == -1:
        return "Aggregate stats should track failed requests."

    if report.find("Strategy Errors: 1") == -1:
        return "Aggregate stats should include strategy error counts."

    if report.find("Warnings: 2") == -1:
        return "Aggregate stats should include warning counts."

    if report.find("Stream Records: 0") != -1:
        return "Stream usage count should be greater than zero."

    return null

func _make_processor() -> RNGProcessor:
    var processor := RNGProcessor.new()
    processor._ready()
    return processor

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

func _remove_file(path: String) -> void:
    if not FileAccess.file_exists(path):
        return
    DirAccess.remove_absolute(path)
