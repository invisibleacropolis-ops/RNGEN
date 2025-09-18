extends RefCounted

const RNGProcessor := preload("res://name_generator/RNGProcessor.gd")
const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")
const ScenarioHelper := preload("res://tests/helpers/rng_processor_scenarios.gd")

const DEBUG_LOG_PATH := "user://debug_rng_processor_headless.txt"

var _started_events: Array[Dictionary] = []
var _completed_events: Array[Dictionary] = []
var _failed_events: Array[Dictionary] = []

func run() -> Dictionary:
    _started_events.clear()
    _completed_events.clear()
    _failed_events.clear()
    var failures: Array[Dictionary] = []

    var processor := RNGProcessor.new()
    processor._ready()

    var debug_rng := DebugRNG.new()
    debug_rng.begin_session({"suite": "rng_processor_headless"})
    debug_rng.attach_to_processor(processor, DEBUG_LOG_PATH)

    processor.connect("generation_started", Callable(self, "_on_generation_started"))
    processor.connect("generation_completed", Callable(self, "_on_generation_completed"))
    processor.connect("generation_failed", Callable(self, "_on_generation_failed"))

    processor.initialize_master_seed(424242)
    debug_rng.record_warning("Headless RNGProcessor scenarios starting.", {"suite": "rng_processor_headless"})

    var scenario_count := 0
    for scenario in ScenarioHelper.collect_default_scenarios(processor):
        scenario_count += 1
        var scenario_name := String(scenario.get("name", ""))
        var scenario_callable := scenario.get("callable")
        if scenario_callable is Callable:
            var message: Variant = scenario_callable.call()
            if message != null:
                failures.append({
                    "name": scenario_name if not scenario_name.is_empty() else "unnamed_scenario",
                    "message": String(message),
                })
        else:
            failures.append({
                "name": scenario_name if not scenario_name.is_empty() else "invalid_scenario_callable",
                "message": "Scenario helper returned a non-callable entry.",
            })

    debug_rng.record_warning("Headless RNGProcessor scenarios completed.", {"suite": "rng_processor_headless"})
    debug_rng.close()

    _append_failures(failures, ScenarioHelper.evaluate_signal_counts(_started_events, _completed_events, _failed_events))
    _append_failures(failures, ScenarioHelper.evaluate_debug_log(DEBUG_LOG_PATH))

    var total_checks := scenario_count + failures.size()
    var failed := failures.size()
    var passed := total_checks - failed

    return {
        "suite": "RNGProcessorHeadless",
        "total": total_checks,
        "passed": passed,
        "failed": failed,
        "failures": failures,
    }

func _append_failures(target: Array[Dictionary], additions: Array[Dictionary]) -> void:
    for failure in additions:
        target.append(failure.duplicate(true))

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
