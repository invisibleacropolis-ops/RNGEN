extends SceneTree

const RNGProcessor := preload("res://name_generator/RNGProcessor.gd")
const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")
const ScenarioHelper := preload("res://tests/helpers/rng_processor_scenarios.gd")

const DEBUG_LOG_PATH := "user://debug_rng_processor_headless.txt"

var _processor: RNGProcessor
var _debug_rng: DebugRNG
var _failures: Array[Dictionary] = []
var _started_events: Array[Dictionary] = []
var _completed_events: Array[Dictionary] = []
var _failed_events: Array[Dictionary] = []

func _initialize() -> void:
    _processor = RNGProcessor.new()
    get_root().add_child(_processor)
    _processor._ready()

    _debug_rng = DebugRNG.new()
    _debug_rng.begin_session({
        "suite": "rng_processor_headless",
    })
    _debug_rng.attach_to_processor(_processor, DEBUG_LOG_PATH)

    _processor.connect("generation_started", Callable(self, "_on_generation_started"))
    _processor.connect("generation_completed", Callable(self, "_on_generation_completed"))
    _processor.connect("generation_failed", Callable(self, "_on_generation_failed"))

    call_deferred("_run")

func _run() -> void:

    _processor.initialize_master_seed(424242)
    _debug_rng.record_warning("Headless RNGProcessor scenarios starting.", {"suite": "rng_processor_headless"})

    for scenario in ScenarioHelper.collect_default_scenarios(_processor):
        var scenario_name := String(scenario.get("name", ""))
        var scenario_callable := scenario.get("callable")
        if scenario_callable is Callable:
            _execute(scenario_name, scenario_callable)
        else:
            _failures.append({
                "name": scenario_name if not scenario_name.is_empty() else "invalid_scenario_callable",
                "message": "Scenario helper returned a non-callable entry.",
            })

    _debug_rng.record_warning("Headless RNGProcessor scenarios completed.", {"suite": "rng_processor_headless"})
    _debug_rng.close()

    _append_failures(ScenarioHelper.evaluate_signal_counts(_started_events, _completed_events, _failed_events))
    _append_failures(ScenarioHelper.evaluate_debug_log(DEBUG_LOG_PATH))

    var exit_code = 0 if _failures.is_empty() else 1
    if exit_code != 0:
        for failure in _failures:
            var name = failure.get("name", "")
            var message = failure.get("message", "")
            push_error("[rng_processor_headless] %s -- %s" % [name, message])

    quit(exit_code)

func _execute(name: String, callable: Callable) -> void:
    var message = callable.call()
    if message == null:
        return
    _failures.append({
        "name": name,
        "message": String(message),
    })

func _append_failures(failures: Array[Dictionary]) -> void:
    for failure in failures:
        _failures.append(failure.duplicate(true))

func _on_generation_started(config: Dictionary, metadata: Dictionary) -> void:
    _started_events.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
    })

func _on_generation_completed(config: Dictionary, result: Variant, metadata: Dictionary) -> void:
    _completed_events.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
        "result": result,
    })

func _on_generation_failed(config: Dictionary, error: Dictionary, metadata: Dictionary) -> void:
    _failed_events.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
        "error": error.duplicate(true),
    })
