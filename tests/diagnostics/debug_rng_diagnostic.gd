extends RefCounted

const DebugRNGScript := preload("res://name_generator/tools/DebugRNG.gd")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("session_logging", func(): return _test_session_logging())
    _run_test("strategy_tracking", func(): return _test_strategy_tracking())

    return {
        "id": "debug_rng",
        "suite": "debug_rng",
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
        "message": str(message),
    })

func _test_session_logging() -> Variant:
    var debug := DebugRNGScript.new()
    debug.begin_session({"test_case": "session_logging"})

    var log_path := _make_temp_log_path("session")
    var processor := MockProcessor.new()
    debug.attach_to_processor(processor, log_path, false)

    var config := {
        "strategy": "omega",
        "seed": 5,
    }
    var metadata := {
        "strategy_id": "omega",
        "seed": 5,
        "rng_stream": "omega::5",
    }

    processor.emit_generation_started(config, metadata)
    processor.emit_generation_completed(config, "generated", metadata)
    processor.emit_generation_failed(config, {
        "code": "intentional_failure",
        "message": "stub",
    }, metadata)

    debug.record_warning("Heads up", {"phase": "post"})
    debug.record_stream_usage("omega::5", {"step": 1})

    var stats: Dictionary = debug._stats
    var message: Variant = null
    message = _merge_message(message, _assert_equal(1, stats.get("calls_started", 0), "calls_started should count generation_started events."))
    message = _merge_message(message, _assert_equal(1, stats.get("calls_completed", 0), "calls_completed should count generation_completed events."))
    message = _merge_message(message, _assert_equal(1, stats.get("calls_failed", 0), "calls_failed should count generation_failed events."))
    message = _merge_message(message, _assert_equal(1, stats.get("warnings", 0), "warnings should track recorded warnings."))
    message = _merge_message(message, _assert_equal(1, stats.get("stream_records", 0), "stream_records should count stream usage entries."))
    if message != null:
        return message

    var stream_entries := debug._log_entries.filter(func(entry): return entry.get("type", "") == "stream_usage")
    message = _merge_message(message, _assert_equal(1, stream_entries.size(), "stream_usage entries should be appended to the log."))
    if message != null:
        return message

    debug.close()

    if not FileAccess.file_exists(log_path):
        return "DebugRNG should serialize a report at %s" % log_path

    var file := FileAccess.open(log_path, FileAccess.READ)
    if file == null:
        return "Unable to open serialized report at %s" % log_path

    var contents := file.get_as_text()
    if contents.find("Debug RNG Report") == -1:
        return "Serialized report should include a report header."
    if contents.find("START") == -1 or contents.find("COMPLETE") == -1 or contents.find("FAIL") == -1:
        return "Serialized report should document generation lifecycle events."
    if contents.find("Warnings") == -1 or contents.find("Heads up") == -1:
        return "Serialized report should include recorded warnings."
    if contents.find("Stream Usage") == -1 or contents.find("omega::5") == -1:
        return "Serialized report should include recorded stream usage entries."

    return null

func _test_strategy_tracking() -> Variant:
    var debug := DebugRNGScript.new()
    debug.begin_session({"test_case": "strategy_tracking"})

    var processor := MockProcessor.new()
    debug.attach_to_processor(processor, _make_temp_log_path("strategy"), false)

    var strategy := MockStrategy.new()
    debug.track_strategy("delta", strategy)

    strategy.emit_generation_error("bad_seed", "message", {"attempt": 1})

    var stats: Dictionary = debug._stats
    var message: Variant = _assert_equal(1, stats.get("strategy_errors", 0), "strategy_errors should increment when tracked strategies emit errors.")
    if message != null:
        return message

    var entries := debug._log_entries.filter(func(entry): return entry.get("type", "") == "strategy_error")
    message = _merge_message(message, _assert_equal(1, entries.size(), "strategy_error entries should be recorded when tracked strategies fail."))
    if message == null:
        var entry: Dictionary = entries[0]
        message = _merge_message(message, _assert_equal("delta", entry.get("strategy_id", ""), "Strategy identifier should be captured in log entries."))
        message = _merge_message(message, _assert_equal("bad_seed", entry.get("code", ""), "Strategy error code should be logged."))
    if message != null:
        return message

    debug.untrack_strategy(strategy)
    strategy.emit_generation_error("bad_seed", "message", {"attempt": 2})

    message = _merge_message(message, _assert_equal(1, debug._stats.get("strategy_errors", 0), "Strategy errors should not increment after untracking."))
    return message

class MockProcessor:
    extends RefCounted

    signal generation_started(config, metadata)
    signal generation_completed(config, result, metadata)
    signal generation_failed(config, error, metadata)

    var debug_rng_requests: Array = []

    func set_debug_rng(instance: Object, propagate: bool) -> void:
        debug_rng_requests.append({
            "instance": instance,
            "propagate": propagate,
        })

    func emit_generation_started(config: Dictionary, metadata: Dictionary) -> void:
        emit_signal("generation_started", config, metadata)

    func emit_generation_completed(config: Dictionary, result: Variant, metadata: Dictionary) -> void:
        emit_signal("generation_completed", config, result, metadata)

    func emit_generation_failed(config: Dictionary, error: Dictionary, metadata: Dictionary) -> void:
        emit_signal("generation_failed", config, error, metadata)

class MockStrategy:
    extends RefCounted

    signal generation_error(code, message, details)

    func emit_generation_error(code: String, message: String, details: Dictionary) -> void:
        emit_signal("generation_error", code, message, details)

func _make_temp_log_path(label: String) -> String:
    var timestamp := Time.get_ticks_usec()
    return "user://debug_rng_%s_%d.txt" % [label, timestamp]

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

func _merge_message(current: Variant, candidate: Variant) -> Variant:
    if current != null:
        return current
    return candidate

func _assert_equal(expected: Variant, actual: Variant, message: String) -> Variant:
    if expected != actual:
        return "%s Expected: %s Actual: %s" % [message, expected, actual]
    return null
