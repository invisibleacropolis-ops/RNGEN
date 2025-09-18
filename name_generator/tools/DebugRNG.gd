extends RefCounted
class_name DebugRNG

## DebugRNG collects detailed telemetry about name generation runs.
##
## The helper can attach to an RNGProcessor instance to record the middleware
## lifecycle and hook into GeneratorStrategy failures. Consumers may also push
## ad-hoc diagnostics (warnings, stream usages, notes) into the log via the
## exposed helper APIs. When the session ends, DebugRNG serializes a structured
## plain-text report so teams can share reproducible investigations.

const DEFAULT_LOG_PATH := "user://debug_rng_report.txt"

var _log_path := DEFAULT_LOG_PATH
var _session_open := false
var _session_metadata: Dictionary = {}
var _log_entries: Array[Dictionary] = []
var _stats := {
    "calls_started": 0,
    "calls_completed": 0,
    "calls_failed": 0,
    "strategy_errors": 0,
    "warnings": 0,
    "stream_records": 0,
}
var _attached_processor: Object = null
var _tracked_strategies: Dictionary = {}
var _session_started_at := ""
var _session_ended_at := ""

func begin_session(metadata: Dictionary = {}) -> void:
    ## Start a new logging session and capture optional metadata to include in
    ## the serialized report.
    _session_open = true
    _session_metadata = metadata.duplicate(true)
    _session_started_at = _current_timestamp()
    _session_ended_at = ""
    _log_entries.clear()
    _stats = {
        "calls_started": 0,
        "calls_completed": 0,
        "calls_failed": 0,
        "strategy_errors": 0,
        "warnings": 0,
        "stream_records": 0,
    }

func attach_to_processor(processor: Object, log_path: String = DEFAULT_LOG_PATH, propagate_to_processor: bool = true) -> void:
    ## Attach DebugRNG to an RNGProcessor so it can observe middleware events.
    if processor == null:
        return

    if log_path.strip_edges() != "":
        _log_path = log_path.strip_edges()

    if _attached_processor != null and is_instance_valid(_attached_processor) and _attached_processor != processor:
        detach_from_processor(_attached_processor)

    _attached_processor = processor

    if processor.has_signal("generation_started"):
        var started_callable := Callable(self, "_on_generation_started")
        if not processor.is_connected("generation_started", started_callable):
            processor.connect("generation_started", started_callable, CONNECT_REFERENCE_COUNTED)
    if processor.has_signal("generation_completed"):
        var completed_callable := Callable(self, "_on_generation_completed")
        if not processor.is_connected("generation_completed", completed_callable):
            processor.connect("generation_completed", completed_callable, CONNECT_REFERENCE_COUNTED)
    if processor.has_signal("generation_failed"):
        var failed_callable := Callable(self, "_on_generation_failed")
        if not processor.is_connected("generation_failed", failed_callable):
            processor.connect("generation_failed", failed_callable, CONNECT_REFERENCE_COUNTED)

    if propagate_to_processor and processor.has_method("set_debug_rng"):
        processor.call("set_debug_rng", self, false)

func detach_from_processor(processor: Object = null) -> void:
    ## Disconnect from the bound RNGProcessor.
    var target := processor if processor != null else _attached_processor
    if target == null or not is_instance_valid(target):
        _attached_processor = null
        return

    if target.has_signal("generation_started"):
        if target.is_connected("generation_started", Callable(self, "_on_generation_started")):
            target.disconnect("generation_started", Callable(self, "_on_generation_started"))
    if target.has_signal("generation_completed"):
        if target.is_connected("generation_completed", Callable(self, "_on_generation_completed")):
            target.disconnect("generation_completed", Callable(self, "_on_generation_completed"))
    if target.has_signal("generation_failed"):
        if target.is_connected("generation_failed", Callable(self, "_on_generation_failed")):
            target.disconnect("generation_failed", Callable(self, "_on_generation_failed"))

    if _attached_processor == target:
        _attached_processor = null

func track_strategy(strategy_id: String, strategy: Object) -> void:
    ## Observe generation_error emissions from a GeneratorStrategy instance.
    if strategy == null:
        return
    var key := strategy.get_instance_id()
    if _tracked_strategies.has(key):
        _tracked_strategies[key]["id"] = strategy_id
        return

    var callable := Callable(self, "_on_strategy_error").bind(strategy_id)
    if strategy.has_signal("generation_error"):
        var error := strategy.connect("generation_error", callable, CONNECT_REFERENCE_COUNTED)
        if error == OK:
            _tracked_strategies[key] = {
                "strategy": strategy,
                "id": strategy_id,
            }

func untrack_strategy(strategy: Object) -> void:
    ## Stop observing a previously tracked strategy.
    if strategy == null:
        return
    var key := strategy.get_instance_id()
    if not _tracked_strategies.has(key):
        return

    var raw_metadata: Variant = _tracked_strategies[key]
    _tracked_strategies.erase(key)

    var metadata: Dictionary = raw_metadata if raw_metadata is Dictionary else {}

    if strategy.has_signal("generation_error"):
        var callable := Callable(self, "_on_strategy_error").bind(metadata.get("id", ""))
        if strategy.is_connected("generation_error", callable):
            strategy.disconnect("generation_error", callable)

func clear_tracked_strategies() -> void:
    ## Disconnect from every tracked strategy.
    for entry in _tracked_strategies.values():
        var metadata: Dictionary = entry if entry is Dictionary else {}
        var tracked_strategy: Object = metadata.get("strategy", null)
        if tracked_strategy != null and is_instance_valid(tracked_strategy):
            var callable := Callable(self, "_on_strategy_error").bind(metadata.get("id", ""))
            if tracked_strategy.has_signal("generation_error") and tracked_strategy.is_connected("generation_error", callable):
                tracked_strategy.disconnect("generation_error", callable)
    _tracked_strategies.clear()

func record_warning(message: String, context: Dictionary = {}) -> void:
    ## Append a warning record to the log so tooling can surface diagnostics
    ## unrelated to explicit failures.
    _stats["warnings"] += 1
    _log_entries.append({
        "type": "warning",
        "timestamp": _current_timestamp(),
        "message": message,
        "context": context.duplicate(true),
    })

func record_stream_usage(stream_name: String, context: Dictionary = {}) -> void:
    ## Track when a deterministic RNG stream is resolved or consumed. This helps
    ## correlate derived RNG state with downstream generation steps.
    _stats["stream_records"] += 1
    _log_entries.append({
        "type": "stream_usage",
        "timestamp": _current_timestamp(),
        "stream": stream_name,
        "context": context.duplicate(true),
    })

func close() -> void:
    ## Finalize the session and write the accumulated report to disk.
    if not _session_open and _log_entries.is_empty():
        return

    _session_open = false
    _session_ended_at = _current_timestamp()

    var lines := _serialize_report()
    var file := FileAccess.open(_log_path, FileAccess.WRITE)
    if file == null:
        push_error("DebugRNG could not open log file at %s" % _log_path)
        return

    for line in lines:
        file.store_line(line)

func dispose() -> void:
    ## Alias for close() to match familiar resource lifecycles.
    close()

func _on_generation_started(config: Dictionary, metadata: Dictionary) -> void:
    _stats["calls_started"] += 1
    _log_entries.append({
        "type": "generation_started",
        "timestamp": _current_timestamp(),
        "config": _duplicate_variant(config),
        "metadata": _duplicate_variant(metadata),
    })

func _on_generation_completed(config: Dictionary, result: Variant, metadata: Dictionary) -> void:
    _stats["calls_completed"] += 1
    _log_entries.append({
        "type": "generation_completed",
        "timestamp": _current_timestamp(),
        "config": _duplicate_variant(config),
        "metadata": _duplicate_variant(metadata),
        "result": _duplicate_variant(result),
    })

func _on_generation_failed(config: Dictionary, error: Dictionary, metadata: Dictionary) -> void:
    _stats["calls_failed"] += 1
    _log_entries.append({
        "type": "generation_failed",
        "timestamp": _current_timestamp(),
        "config": _duplicate_variant(config),
        "metadata": _duplicate_variant(metadata),
        "error": _duplicate_variant(error),
    })

func _on_strategy_error(code: String, message: String, details: Dictionary, strategy_id: String) -> void:
    _stats["strategy_errors"] += 1
    _log_entries.append({
        "type": "strategy_error",
        "timestamp": _current_timestamp(),
        "strategy_id": strategy_id,
        "code": code,
        "message": message,
        "details": _duplicate_variant(details),
    })

func _serialize_report() -> PackedStringArray:
    var lines := PackedStringArray()
    lines.append("Debug RNG Report")
    lines.append("================")
    lines.append("")

    lines.append("Session Metadata")
    lines.append("----------------")
    lines.append("Started At: %s" % _session_started_at)
    lines.append("Ended At: %s" % _session_ended_at)
    for key in _session_metadata.keys():
        lines.append("%s: %s" % [String(key), _stringify_value(_session_metadata[key])])
    lines.append("")

    lines.append("Generation Timeline")
    lines.append("-------------------")
    var index := 1
    for entry in _log_entries:
        match entry.get("type", ""):
            "generation_started":
                lines.append("[%d] START %s strategy=%s seed=%s stream=%s" % [
                    index,
                    entry["timestamp"],
                    entry.get("metadata", {}).get("strategy_id", ""),
                    entry.get("metadata", {}).get("seed", ""),
                    entry.get("metadata", {}).get("rng_stream", ""),
                ])
                index += 1
            "generation_completed":
                lines.append("[%d] COMPLETE %s strategy=%s result=%s" % [
                    index,
                    entry["timestamp"],
                    entry.get("metadata", {}).get("strategy_id", ""),
                    _stringify_value(entry.get("result", "")),
                ])
                index += 1
            "generation_failed":
                lines.append("[%d] FAIL %s strategy=%s code=%s" % [
                    index,
                    entry["timestamp"],
                    entry.get("metadata", {}).get("strategy_id", ""),
                    entry.get("error", {}).get("code", ""),
                ])
                index += 1
            "strategy_error":
                lines.append("[%d] STRATEGY_ERROR %s strategy=%s code=%s message=%s" % [
                    index,
                    entry["timestamp"],
                    entry.get("strategy_id", ""),
                    entry.get("code", ""),
                    entry.get("message", ""),
                ])
                index += 1
            _:
                continue
    if index == 1:
        lines.append("No generation activity recorded.")
    lines.append("")

    lines.append("Warnings")
    lines.append("--------")
    var warnings := _log_entries.filter(func(e): return e.get("type", "") == "warning")
    if warnings.is_empty():
        lines.append("None recorded.")
    else:
        for warning in warnings:
            lines.append("- %s -- %s %s" % [
                warning.get("timestamp", ""),
                warning.get("message", ""),
                _stringify_value(warning.get("context", {})),
            ])
    lines.append("")

    lines.append("Stream Usage")
    lines.append("------------")
    var streams := _log_entries.filter(func(e): return e.get("type", "") == "stream_usage")
    if streams.is_empty():
        lines.append("No stream usage recorded.")
    else:
        for stream in streams:
            lines.append("- %s -- %s %s" % [
                stream.get("timestamp", ""),
                stream.get("stream", ""),
                _stringify_value(stream.get("context", {})),
            ])
    lines.append("")

    lines.append("Aggregate Statistics")
    lines.append("---------------------")
    lines.append("Total Calls: %d" % _stats.get("calls_started", 0))
    lines.append("Successful Calls: %d" % _stats.get("calls_completed", 0))
    lines.append("Failed Calls: %d" % _stats.get("calls_failed", 0))
    lines.append("Strategy Errors: %d" % _stats.get("strategy_errors", 0))
    lines.append("Warnings: %d" % _stats.get("warnings", 0))
    lines.append("Stream Records: %d" % _stats.get("stream_records", 0))

    return lines

func _current_timestamp() -> String:
    return Time.get_datetime_string_from_system(false, true)

func _stringify_value(value: Variant) -> String:
    if value is String:
        return value
    var json := JSON.new()
    return json.stringify(value)

func _duplicate_variant(value: Variant) -> Variant:
    if value is Dictionary:
        return (value as Dictionary).duplicate(true)
    if value is Array:
        return (value as Array).duplicate(true)
    return value
