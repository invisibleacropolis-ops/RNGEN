extends RefCounted

const RNGProcessor := preload("res://name_generator/RNGProcessor.gd")
const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")
const ScenarioHelper := preload("res://tests/helpers/rng_processor_scenarios.gd")

const DEBUG_LOG_PATH := "user://debug_rng_processor_headless.txt"

func run() -> Dictionary:
    var processor := RNGProcessor.new()
    processor._ready()

    var debug_rng := DebugRNG.new()
    debug_rng.begin_session({
        "suite": "rng_processor_headless",
    })
    debug_rng.attach_to_processor(processor, DEBUG_LOG_PATH)

    var started_events: Array[Dictionary] = []
    var completed_events: Array[Dictionary] = []
    var failed_events: Array[Dictionary] = []

    processor.connect("generation_started", Callable(self, "_capture_started").bind(started_events))
    processor.connect("generation_completed", Callable(self, "_capture_completed").bind(completed_events))
    processor.connect("generation_failed", Callable(self, "_capture_failed").bind(failed_events))

    processor.initialize_master_seed(424242)
    debug_rng.record_warning("Headless RNGProcessor scenarios starting.", {"suite": "rng_processor_headless"})

    var failures: Array[Dictionary] = []
    var scenarios := ScenarioHelper.collect_default_scenarios(processor)
    for scenario in scenarios:
        var scenario_name := String(scenario.get("name", ""))
        var scenario_callable := scenario.get("callable")
        if scenario_callable is Callable:
            var message := scenario_callable.call()
            if message != null:
                failures.append({
                    "name": scenario_name,
                    "message": String(message),
                })
        else:
            failures.append({
                "name": scenario_name if not scenario_name.is_empty() else "invalid_scenario_callable",
                "message": "Scenario helper returned a non-callable entry.",
            })

    debug_rng.record_warning("Headless RNGProcessor scenarios completed.", {"suite": "rng_processor_headless"})
    debug_rng.close()

    failures += ScenarioHelper.evaluate_signal_counts(started_events, completed_events, failed_events)
    failures += ScenarioHelper.evaluate_debug_log(DEBUG_LOG_PATH)

    var scenario_checks := scenarios.size()
    var signal_checks := ScenarioHelper.expected_signal_counts().keys().size()
    var debug_markers := ScenarioHelper.debug_log_markers()
    var debug_checks := 2 + debug_markers.size()  # existence + open + markers
    var total_checks := scenario_checks + signal_checks + debug_checks
    var failed := failures.size()
    var passed := max(total_checks - failed, 0)

    processor.free()

    return {
        "id": "rng_processor_headless",
        "name": "RNGProcessor Headless Diagnostic",
        "suite": "rng_processor_headless",
        "total": total_checks,
        "passed": passed,
        "failed": failed,
        "failures": failures.duplicate(true),
    }

func _capture_started(config: Dictionary, metadata: Dictionary, bucket: Array) -> void:
    bucket.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
    })

func _capture_completed(config: Dictionary, result: Variant, metadata: Dictionary, bucket: Array) -> void:
    bucket.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
        "result": result,
    })

func _capture_failed(config: Dictionary, error: Dictionary, metadata: Dictionary, bucket: Array) -> void:
    bucket.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
        "error": error.duplicate(true),
    })
