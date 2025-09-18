extends Node
## Controller node that exposes RNGProcessor middleware APIs to the Platform GUI.
##
## The controller hides the Engine singleton lookups, proxies common middleware
## calls, and forwards RNGProcessor signals to the Platform GUI event bus so
## panels can subscribe without touching the autoload directly.

const TestSuiteRunner := preload("res://tests/test_suite_runner.gd")

signal qa_run_started(run_id: String, request: Dictionary)
signal qa_run_output(run_id: String, line: String)
signal qa_run_completed(run_id: String, payload: Dictionary)

@export var event_bus_path: NodePath

var _rng_processor_override: Object = null
var _cached_rng_processor: Object = null
var _connected_processor: Object = null
var _event_bus_override: Object = null
var _cached_event_bus: Object = null
var _latest_generation_metadata: Dictionary = {}
var _qa_runner_override: Object = null
var _qa_runner: Object = null
var _qa_active_request: Dictionary = {}
var _qa_log_callable: Callable = Callable()
var _qa_run_in_progress: bool = false
var _qa_recent_runs: Array = []
var _qa_yield_between_logs: bool = true

const _MAX_QA_RUN_HISTORY := 5

func _ready() -> void:
    _refresh_event_bus()
    _refresh_rng_processor()
    _ensure_processor_connections()

func initialize_master_seed(seed_value: int) -> void:
    var processor := _get_rng_processor()
    if processor == null:
        push_warning("RNGProcessor singleton unavailable; initialize_master_seed skipped.")
        return
    if processor.has_method("initialize_master_seed"):
        processor.call("initialize_master_seed", seed_value)
    elif processor.has_method("set_master_seed"):
        processor.call("set_master_seed", seed_value)

func reset_master_seed() -> int:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("reset_master_seed"):
        push_warning("RNGProcessor singleton unavailable; returning default master seed value.")
        return 0
    var result: Variant = processor.call("reset_master_seed")
    return int(result)

func get_master_seed() -> int:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("get_master_seed"):
        push_warning("RNGProcessor singleton unavailable; returning default master seed value.")
        return 0
    return int(processor.call("get_master_seed"))

func randomize_master_seed() -> int:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("randomize_master_seed"):
        push_warning("RNGProcessor singleton unavailable; returning default master seed value.")
        return 0
    var result: Variant = processor.call("randomize_master_seed")
    return int(result)

func list_strategies() -> PackedStringArray:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("list_strategies"):
        return PackedStringArray()
    var strategies: Variant = processor.call("list_strategies")
    if strategies is PackedStringArray:
        return strategies
    var packed := PackedStringArray()
    if strategies is Array:
        for value in strategies:
            packed.append(String(value))
    return packed

func describe_strategies() -> Dictionary:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("describe_strategies"):
        return {}
    var payload: Variant = processor.call("describe_strategies")
    if payload is Dictionary:
        return (payload as Dictionary).duplicate(true)
    return {}

func describe_rng_streams() -> Dictionary:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("describe_rng_streams"):
        return {}
    var payload: Variant = processor.call("describe_rng_streams")
    if payload is Dictionary:
        return (payload as Dictionary).duplicate(true)
    return {}

func describe_stream_routing(stream_names: PackedStringArray = PackedStringArray()) -> Dictionary:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("describe_stream_routing"):
        return {}
    var payload: Variant = processor.call("describe_stream_routing", stream_names)
    if payload is Dictionary:
        return (payload as Dictionary).duplicate(true)
    return {}

func export_seed_state() -> Dictionary:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("export_rng_state"):
        return {}
    var payload: Variant = processor.call("export_rng_state")
    if payload is Dictionary:
        return (payload as Dictionary).duplicate(true)
    return {}

func import_seed_state(payload: Variant) -> void:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("import_rng_state"):
        push_warning("RNGProcessor singleton unavailable; import_seed_state skipped.")
        return
    processor.call("import_rng_state", payload)

func generate(config: Variant, override_rng: RandomNumberGenerator = null) -> Variant:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("generate"):
        return {
            "code": "missing_rng_processor",
            "message": "RNGProcessor singleton unavailable; request cannot be processed.",
            "details": {},
        }
    return processor.call("generate", config, override_rng)

func set_debug_rng(debug_rng: Object, attach_to_debug: bool = true) -> void:
    var processor := _get_rng_processor()
    if processor == null:
        push_warning("RNGProcessor singleton unavailable; set_debug_rng skipped.")
        return
    if processor.has_method("set_debug_rng"):
        processor.call("set_debug_rng", debug_rng, attach_to_debug)

func get_debug_rng() -> Object:
    var processor := _get_rng_processor()
    if processor == null or not processor.has_method("get_debug_rng"):
        return null
    return processor.call("get_debug_rng")

func get_latest_generation_metadata() -> Dictionary:
    return _latest_generation_metadata.duplicate(true)

func get_available_qa_diagnostics() -> Array:
    ## Return the merged diagnostic catalog used by the QA panel.
    var diagnostics := TestSuiteRunner.list_available_diagnostics()
    var copies: Array = []
    for entry in diagnostics:
        if entry is Dictionary:
            copies.append((entry as Dictionary).duplicate(true))
        else:
            copies.append(entry)
    return copies

func get_recent_qa_runs() -> Array:
    ## Return cached QA run summaries for panel display.
    var history: Array = []
    for record in _qa_recent_runs:
        if record is Dictionary:
            history.append((record as Dictionary).duplicate(true))
        else:
            history.append(record)
    return history

func is_qa_run_active() -> bool:
    ## Indicate whether an automated QA run is currently executing.
    return _qa_run_in_progress

func run_full_test_suite() -> String:
    ## Launch the complete regression manifest used by run_all_tests.gd.
    return _launch_qa_run({
        "mode": "manifest",
        "manifest_path": TestSuiteRunner.DEFAULT_MANIFEST_PATH,
        "label": "Full suite",
    })

func run_targeted_diagnostic(diagnostic_id: String) -> String:
    ## Launch a specific diagnostic by manifest ID.
    return _launch_qa_run({
        "mode": "diagnostic",
        "diagnostic_id": diagnostic_id,
        "label": "Diagnostic %s" % diagnostic_id,
    })

func set_qa_runner_override(runner: Object) -> void:
    ## Inject a deterministic QA runner for tests.
    _qa_runner_override = runner

func clear_qa_runner_override() -> void:
    ## Clear the QA runner override and fall back to runtime instances.
    _qa_runner_override = null

func set_qa_stream_yield(enabled: bool) -> void:
    ## Configure whether QA runs yield between log lines (used by tests).
    _qa_yield_between_logs = enabled

func set_rng_processor_override(processor: Object) -> void:
    _rng_processor_override = processor
    _cached_rng_processor = null
    _connected_processor = null
    _ensure_processor_connections()

func clear_rng_processor_override() -> void:
    _rng_processor_override = null
    _cached_rng_processor = null
    _connected_processor = null
    _ensure_processor_connections()

func set_event_bus_override(event_bus: Object) -> void:
    _event_bus_override = event_bus
    _cached_event_bus = null
    _refresh_event_bus()

func clear_event_bus_override() -> void:
    _event_bus_override = null
    _cached_event_bus = null
    _refresh_event_bus()

func refresh_connections() -> void:
    _refresh_event_bus()
    _refresh_rng_processor()
    _ensure_processor_connections()

func _launch_qa_run(request: Dictionary) -> String:
    if _qa_run_in_progress:
        push_warning("QA run already in progress; request ignored.")
        return ""

    var runner := _get_qa_runner()
    if runner == null:
        push_warning("QA test runner unavailable; request skipped.")
        return ""

    var run_id := "qa_%d" % Time.get_ticks_msec()
    var prepared := request.duplicate(true)
    prepared["run_id"] = run_id
    prepared["requested_at"] = Time.get_ticks_msec()
    prepared["yield_frames"] = _qa_yield_between_logs

    _qa_runner = runner
    _qa_runner.forward_to_console = false
    _qa_active_request = prepared
    _qa_run_in_progress = true

    var log_callable := Callable(self, "_on_qa_runner_log").bind(run_id)
    _qa_log_callable = log_callable
    if not _qa_runner.log_emitted.is_connected(log_callable):
        _qa_runner.log_emitted.connect(log_callable, CONNECT_DEFERRED)

    emit_signal("qa_run_started", run_id, prepared.duplicate(true))
    call_deferred("_process_active_qa_run")
    return run_id

func _get_qa_runner() -> Object:
    if _qa_runner_override != null and _is_object_valid(_qa_runner_override):
        return _qa_runner_override
    return TestSuiteRunner.new()

func _normalize_logs(logs_variant: Variant) -> PackedStringArray:
    if logs_variant is PackedStringArray:
        var duplicate := PackedStringArray()
        duplicate.append_array(logs_variant)
        return duplicate
    if logs_variant is Array:
        var converted := PackedStringArray()
        for value in logs_variant:
            converted.append(String(value))
        return converted
    return PackedStringArray()

func _strip_logs(result: Variant) -> Dictionary:
    var summary := {}
    if not (result is Dictionary):
        return summary
    var dictionary: Dictionary = result
    for key in dictionary.keys():
        if key == "logs":
            continue
        summary[key] = _duplicate_variant(dictionary[key])
    return summary

func _process_active_qa_run() -> void:
    var request := _qa_active_request.duplicate(true)
    var runner := _qa_runner
    if runner == null:
        _finish_qa_run(request, {
            "exit_code": 1,
            "logs": PackedStringArray(["QA runner unavailable."]),
        })
        return

    var mode := String(request.get("mode", "manifest"))
    var yield_frames := bool(request.get("yield_frames", _qa_yield_between_logs))
    var result: Dictionary = {}

    if mode == "diagnostic":
        if runner.has_method("run_single_diagnostic"):
            var diagnostic_id := String(request.get("diagnostic_id", ""))
            var diagnostic_result_variant := runner.call("run_single_diagnostic", diagnostic_id, yield_frames)
            if diagnostic_result_variant is GDScriptFunctionState:
                diagnostic_result_variant = await diagnostic_result_variant
            if diagnostic_result_variant is Dictionary:
                result = diagnostic_result_variant
                result["diagnostic_id"] = diagnostic_id
            else:
                result = {
                    "exit_code": 1,
                    "logs": PackedStringArray(["Diagnostic runner returned an unexpected payload."]),
                }
        else:
            result = {
                "exit_code": 1,
                "logs": PackedStringArray(["QA runner does not implement run_single_diagnostic()."]),
            }
    else:
        if runner.has_method("run_manifest"):
            var manifest_path := String(request.get("manifest_path", TestSuiteRunner.DEFAULT_MANIFEST_PATH))
            var manifest_result_variant := runner.call("run_manifest", manifest_path, yield_frames)
            if manifest_result_variant is GDScriptFunctionState:
                manifest_result_variant = await manifest_result_variant
            if manifest_result_variant is Dictionary:
                result = manifest_result_variant
            else:
                result = {
                    "exit_code": 1,
                    "logs": PackedStringArray(["Manifest runner returned an unexpected payload."]),
                }
        else:
            result = {
                "exit_code": 1,
                "logs": PackedStringArray(["QA runner does not implement run_manifest()."]),
            }

    _finish_qa_run(request, result)

func _finish_qa_run(request: Dictionary, result: Dictionary) -> void:
    var run_id := String(request.get("run_id", ""))
    var logs := _normalize_logs(result.get("logs", PackedStringArray()))
    var log_path := _persist_qa_log(run_id, logs)
    var summary := _strip_logs(result)

    summary["run_id"] = run_id
    summary["log_path"] = log_path
    summary["mode"] = String(request.get("mode", ""))
    summary["label"] = String(request.get("label", summary.get("mode", "")))
    summary["diagnostic_id"] = String(request.get("diagnostic_id", ""))
    summary["requested_at"] = int(request.get("requested_at", Time.get_ticks_msec()))
    summary["completed_at"] = Time.get_ticks_msec()
    summary["exit_code"] = int(summary.get("exit_code", result.get("exit_code", 1)))

    _qa_recent_runs.insert(0, summary.duplicate(true))
    if _qa_recent_runs.size() > _MAX_QA_RUN_HISTORY:
        _qa_recent_runs.resize(_MAX_QA_RUN_HISTORY)

    var payload := summary.duplicate(true)
    payload["request"] = request.duplicate(true)
    payload["result"] = summary.duplicate(true)
    payload["logs"] = logs

    emit_signal("qa_run_completed", run_id, payload)

    if _qa_runner != null and _qa_log_callable.is_valid() and _qa_runner.log_emitted.is_connected(_qa_log_callable):
        _qa_runner.log_emitted.disconnect(_qa_log_callable)

    _qa_runner = null
    _qa_log_callable = Callable()
    _qa_active_request = {}
    _qa_run_in_progress = false

func _persist_qa_log(run_id: String, logs: PackedStringArray) -> String:
    if logs.is_empty():
        return ""

    var dir_path := "user://qa_runs"
    var absolute := ProjectSettings.globalize_path(dir_path)
    DirAccess.make_dir_recursive_absolute(absolute)

    var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
    var file_name := "%s_%s.log" % [timestamp, run_id]
    var full_path := "%s/%s" % [dir_path, file_name]

    var file := FileAccess.open(full_path, FileAccess.WRITE)
    if file == null:
        return ""
    for line in logs:
        file.store_line(String(line))
    file.close()
    return full_path

func _on_qa_runner_log(run_id: String, line: String) -> void:
    emit_signal("qa_run_output", run_id, String(line))

func _refresh_rng_processor() -> void:
    _cached_rng_processor = null

func _refresh_event_bus() -> void:
    _cached_event_bus = null

func _get_rng_processor() -> Object:
    if _rng_processor_override != null and _is_object_valid(_rng_processor_override):
        return _rng_processor_override
    if _cached_rng_processor != null and _is_object_valid(_cached_rng_processor):
        return _cached_rng_processor
    if Engine.has_singleton("RNGProcessor"):
        var candidate := Engine.get_singleton("RNGProcessor")
        if _is_object_valid(candidate) and candidate.has_method("generate"):
            _cached_rng_processor = candidate
            return _cached_rng_processor
    return null

func _get_event_bus() -> Object:
    if _event_bus_override != null and _is_object_valid(_event_bus_override):
        return _event_bus_override
    if _cached_event_bus != null and _is_object_valid(_cached_event_bus):
        return _cached_event_bus
    if event_bus_path != NodePath("") and has_node(event_bus_path):
        var node := get_node(event_bus_path)
        if node != null:
            _cached_event_bus = node
            return _cached_event_bus
    if Engine.has_singleton("PlatformGUIEventBus"):
        var singleton := Engine.get_singleton("PlatformGUIEventBus")
        if _is_object_valid(singleton):
            _cached_event_bus = singleton
            return _cached_event_bus
    return null

func _ensure_processor_connections() -> void:
    var processor := _get_rng_processor()
    if processor == null:
        return
    _connect_processor_signal(processor, "generation_started", Callable(self, "_on_generation_started"))
    _connect_processor_signal(processor, "generation_completed", Callable(self, "_on_generation_completed"))
    _connect_processor_signal(processor, "generation_failed", Callable(self, "_on_generation_failed"))
    _connected_processor = processor

func _connect_processor_signal(processor: Object, signal_name: String, callable: Callable) -> void:
    if not processor.has_signal(signal_name):
        return
    if processor.is_connected(signal_name, callable):
        return
    processor.connect(signal_name, callable, CONNECT_REFERENCE_COUNTED)

func _on_generation_started(config: Dictionary, metadata: Dictionary) -> void:
    _latest_generation_metadata = metadata.duplicate(true)
    var payload: Dictionary = {
        "type": "generation_started",
        "config": _duplicate_variant(config),
        "metadata": _latest_generation_metadata.duplicate(true),
        "timestamp": Time.get_ticks_msec(),
    }
    _publish_event("rng_generation_started", payload)

func _on_generation_completed(config: Dictionary, result: Variant, metadata: Dictionary) -> void:
    _latest_generation_metadata = metadata.duplicate(true)
    var payload: Dictionary = {
        "type": "generation_completed",
        "config": _duplicate_variant(config),
        "result": _duplicate_variant(result),
        "metadata": _latest_generation_metadata.duplicate(true),
        "timestamp": Time.get_ticks_msec(),
    }
    _publish_event("rng_generation_completed", payload)

func _on_generation_failed(config: Dictionary, error: Dictionary, metadata: Dictionary) -> void:
    _latest_generation_metadata = metadata.duplicate(true)
    var payload: Dictionary = {
        "type": "generation_failed",
        "config": _duplicate_variant(config),
        "error": _duplicate_variant(error),
        "metadata": _latest_generation_metadata.duplicate(true),
        "timestamp": Time.get_ticks_msec(),
    }
    _publish_event("rng_generation_failed", payload)

func _publish_event(event_name: String, payload: Dictionary) -> void:
    var bus := _get_event_bus()
    if bus == null:
        return
    if bus.has_method("publish"):
        bus.call("publish", event_name, payload.duplicate(true))
        return
    if bus.has_signal("event_published"):
        bus.emit_signal("event_published", event_name, payload.duplicate(true))

func _duplicate_variant(value: Variant) -> Variant:
    if value is Dictionary:
        return (value as Dictionary).duplicate(true)
    if value is Array:
        return (value as Array).duplicate(true)
    return value

func _is_object_valid(candidate: Object) -> bool:
    if candidate == null:
        return false
    if candidate is Node:
        return is_instance_valid(candidate)
    return true
