extends RefCounted

const CONTROLLER_SCENE := preload("res://addons/platform_gui/controllers/RNGProcessorController.tscn")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("wraps_rng_processor_api", func(): _test_wraps_rng_processor_api())
    _run_test("forwards_generation_signals", func(): _test_forwards_generation_signals())
    _run_test("exposes_debug_rng_helpers", func(): _test_exposes_debug_rng_helpers())
    _run_test("exposes_seed_dashboard_helpers", func(): _test_exposes_seed_dashboard_helpers())
    _run_test("manages_qa_runs", func(): _test_manages_qa_runs())

    return {
        "suite": "Platform GUI RNGProcessor Controller",
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

func _test_wraps_rng_processor_api() -> Variant:
    var processor := StubRNGProcessor.new()
    var event_bus := StubEventBus.new()
    var controller := _make_controller(processor, event_bus)

    controller.initialize_master_seed(4242)
    if processor.initialize_calls.size() != 1 or processor.initialize_calls[0] != 4242:
        return "initialize_master_seed should forward to the processor."

    processor.reset_return_value = 8080
    var reset_value := controller.reset_master_seed()
    if reset_value != 8080:
        return "reset_master_seed should forward return values."

    processor.strategies = PackedStringArray(["alpha", "beta"])
    var strategies := controller.list_strategies()
    if strategies.size() != 2 or strategies[0] != "alpha" or strategies[1] != "beta":
        return "list_strategies must proxy PackedStringArray responses."

    var descriptions := controller.describe_strategies()
    if descriptions.get("wordlist", {}).get("id", "") != "wordlist":
        return "describe_strategies should return metadata dictionaries."
    descriptions["wordlist"]["notes"] = "mutated"
    if processor.descriptions.get("wordlist", {}).has("notes"):
        return "describe_strategies must duplicate dictionaries to avoid side effects."

    var config := {"strategy": "wordlist"}
    var result := controller.generate(config)
    if result != processor.generate_result:
        return "generate should return the processor payload."
    if processor.last_generate_config == null:
        return "generate must pass the configuration to the processor."

    return null

func _test_forwards_generation_signals() -> Variant:
    var processor := StubRNGProcessor.new()
    var event_bus := StubEventBus.new()
    var controller := _make_controller(processor, event_bus)

    var start_config := {"strategy": "wordlist"}
    var start_metadata := {"rng_stream": "seeded::wordlist"}
    processor.emit_generation_started(start_config, start_metadata)

    if event_bus.events.size() != 1:
        return "generation_started should publish exactly one event."
    var started := event_bus.events[0]
    if started.get("name", "") != "rng_generation_started":
        return "generation_started events must use the rng_generation_started channel."
    var started_payload: Dictionary = started.get("payload", {})
    if started_payload.get("type", "") != "generation_started":
        return "generation_started payload should indicate its type."
    start_config["strategy"] = "mutated"
    if started_payload.get("config", {}).get("strategy", "") != "wordlist":
        return "generation_started payload should duplicate request config dictionaries."
    start_metadata["rng_stream"] = "mutated"
    if started_payload.get("metadata", {}).get("rng_stream", "") != "seeded::wordlist":
        return "generation_started payload should duplicate metadata dictionaries."

    var tracked_metadata := controller.get_latest_generation_metadata()
    if tracked_metadata.get("rng_stream", "") != "seeded::wordlist":
        return "Controller should expose the latest metadata snapshot."
    tracked_metadata["rng_stream"] = "tampered"
    if controller.get_latest_generation_metadata().get("rng_stream", "") != "seeded::wordlist":
        return "Metadata accessor must provide defensive copies."

    var complete_config := {"strategy": "wordlist"}
    var complete_result := {"value": "success"}
    var complete_metadata := {"rng_stream": "wordlist::complete"}
    processor.emit_generation_completed(complete_config, complete_result, complete_metadata)
    if event_bus.events.size() != 2:
        return "generation_completed should publish a follow-up event."
    var completed := event_bus.events[1]
    if completed.get("name", "") != "rng_generation_completed":
        return "generation_completed events must use the rng_generation_completed channel."
    var completed_payload: Dictionary = completed.get("payload", {})
    if completed_payload.get("result", {}).get("value", "") != "success":
        return "generation_completed payload should include result data."

    var failure_config := {"strategy": "wordlist"}
    var failure_error := {"code": "strategy_error"}
    var failure_metadata := {"rng_stream": "wordlist::failure"}
    processor.emit_generation_failed(failure_config, failure_error, failure_metadata)
    if event_bus.events.size() != 3:
        return "generation_failed should publish an error event."
    var failed := event_bus.events[2]
    if failed.get("name", "") != "rng_generation_failed":
        return "generation_failed events must use the rng_generation_failed channel."
    var failed_payload: Dictionary = failed.get("payload", {})
    if failed_payload.get("error", {}).get("code", "") != "strategy_error":
        return "generation_failed payload should include the error dictionary."

    return null

func _test_exposes_debug_rng_helpers() -> Variant:
    var processor := StubRNGProcessor.new()
    var event_bus := StubEventBus.new()
    var controller := _make_controller(processor, event_bus)

    controller.set_debug_rng("debug_instance", false)
    if processor.last_debug_rng != "debug_instance" or processor.last_attach_to_debug != false:
        return "set_debug_rng should proxy debug helper wiring options."

    processor.debug_rng_return_value = "active_debug_rng"
    if controller.get_debug_rng() != "active_debug_rng":
        return "get_debug_rng should proxy through to the processor."

    return null

func _test_exposes_seed_dashboard_helpers() -> Variant:
    var processor := StubRNGProcessor.new()
    var event_bus := StubEventBus.new()
    var controller := _make_controller(processor, event_bus)

    processor.master_seed = 42
    if controller.get_master_seed() != 42:
        return "get_master_seed should proxy the processor value."

    processor.randomize_return_value = 77
    if controller.randomize_master_seed() != 77:
        return "randomize_master_seed should forward processor results."

    var streams := controller.describe_rng_streams()
    if streams.get("mode", "") != "rng_manager":
        return "describe_rng_streams should duplicate the processor payload."
    streams["mode"] = "tampered"
    if processor.stream_payload.get("mode", "") != "rng_manager":
        return "describe_rng_streams must protect the processor payload from mutation."

    var routing := controller.describe_stream_routing(PackedStringArray(["alpha"]))
    if routing.get("requested", "") != "alpha":
        return "describe_stream_routing should forward requested stream names."
    if processor.last_routing_request.size() != 1 or processor.last_routing_request[0] != "alpha":
        return "describe_stream_routing should forward the provided stream filter."

    var export_payload := controller.export_seed_state()
    if export_payload.get("master_seed", 0) != 42:
        return "export_seed_state should duplicate the processor payload."

    controller.import_seed_state({"master_seed": 99})
    if processor.import_payloads.size() != 1:
        return "import_seed_state should forward payloads to the processor."

    return null

func _test_manages_qa_runs() -> Variant:
    var processor := StubRNGProcessor.new()
    var event_bus := StubEventBus.new()
    var controller := _make_controller(processor, event_bus)

    var runner := StubQARunner.new()
    controller.set_qa_runner_override(runner)
    controller.set_qa_stream_yield(false)

    var started_events: Array = []
    var output_events: Array = []
    var completed_events: Array = []

    controller.qa_run_started.connect(func(run_id: String, request: Dictionary): started_events.append({"id": run_id, "request": request.duplicate(true)}), CONNECT_REFERENCE_COUNTED)
    controller.qa_run_output.connect(func(run_id: String, line: String): output_events.append({"id": run_id, "line": line}), CONNECT_REFERENCE_COUNTED)
    controller.qa_run_completed.connect(func(run_id: String, payload: Dictionary): completed_events.append({"id": run_id, "payload": payload.duplicate(true)}), CONNECT_REFERENCE_COUNTED)

    var run_id := controller.run_full_test_suite()
    if run_id == "":
        return "run_full_test_suite should return a run identifier."

    controller._process_active_qa_run()

    if started_events.size() != 1:
        return "qa_run_started should emit exactly once."

    if output_events.size() != runner.logs.size():
        return "qa_run_output should relay runner log entries."

    if completed_events.size() != 1:
        return "qa_run_completed should emit when the run finishes."

    var completion := completed_events[0].get("payload", {})
    if completion.get("result", {}).get("exit_code", 1) != 0:
        return "Completion payload should report a passing exit code."

    var history := controller.get_recent_qa_runs()
    if history.size() != 1:
        return "Controller should cache recent QA runs."

    var record: Dictionary = history[0]
    if String(record.get("log_path", "")) == "":
        return "QA run should persist a log path for later inspection."

    return null

func _make_controller(processor: StubRNGProcessor, event_bus: StubEventBus) -> Node:
    var controller: Node = CONTROLLER_SCENE.instantiate()
    controller.set_rng_processor_override(processor)
    controller.set_event_bus_override(event_bus)
    controller._ready()
    return controller

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

class StubRNGProcessor:
    extends Node

    signal generation_started(config: Dictionary, metadata: Dictionary)
    signal generation_completed(config: Dictionary, result: Variant, metadata: Dictionary)
    signal generation_failed(config: Dictionary, error: Dictionary, metadata: Dictionary)

    var initialize_calls: Array[int] = []
    var reset_return_value: int = 0
    var strategies: PackedStringArray = PackedStringArray(["wordlist"])
    var descriptions: Dictionary = {
        "wordlist": {"id": "wordlist"},
    }
    var generate_result: Variant = {"generated": true}
    var last_generate_config: Variant = null
    var last_generate_override: Variant = null
    var last_debug_rng: Variant = null
    var last_attach_to_debug: bool = true
    var debug_rng_return_value: Variant = null
    var master_seed: int = 0
    var randomize_return_value: int = 0
    var stream_payload: Dictionary = {"mode": "rng_manager", "streams": {"alpha": {"seed": 1, "state": 2}}}
    var routing_payload: Dictionary = {"requested": "alpha"}
    var export_payload: Dictionary = {"master_seed": 42}
    var last_routing_request: PackedStringArray = PackedStringArray()
    var import_payloads: Array = []

    func initialize_master_seed(seed_value: int) -> void:
        initialize_calls.append(seed_value)

    func reset_master_seed() -> int:
        return reset_return_value

    func get_master_seed() -> int:
        return master_seed

    func randomize_master_seed() -> int:
        return randomize_return_value

    func list_strategies() -> PackedStringArray:
        return strategies

    func describe_strategies() -> Dictionary:
        return descriptions

    func describe_rng_streams() -> Dictionary:
        return stream_payload

    func describe_stream_routing(stream_names: PackedStringArray = PackedStringArray()) -> Dictionary:
        last_routing_request = PackedStringArray(stream_names)
        return routing_payload

    func export_rng_state() -> Dictionary:
        return export_payload

    func import_rng_state(payload: Variant) -> void:
        import_payloads.append(payload)

    func generate(config: Variant, override_rng: RandomNumberGenerator = null) -> Variant:
        last_generate_config = config
        last_generate_override = override_rng
        return generate_result

    func set_debug_rng(debug_rng: Variant, attach_to_debug: bool = true) -> void:
        last_debug_rng = debug_rng
        last_attach_to_debug = attach_to_debug

    func get_debug_rng() -> Variant:
        return debug_rng_return_value

    func emit_generation_started(config: Dictionary, metadata: Dictionary) -> void:
        emit_signal("generation_started", config, metadata)

    func emit_generation_completed(config: Dictionary, result: Variant, metadata: Dictionary) -> void:
        emit_signal("generation_completed", config, result, metadata)

    func emit_generation_failed(config: Dictionary, error: Dictionary, metadata: Dictionary) -> void:
        emit_signal("generation_failed", config, error, metadata)

class StubEventBus:
    extends Node

    var events: Array[Dictionary] = []

    func publish(event_name: String, payload: Dictionary) -> void:
        events.append({
            "name": event_name,
            "payload": payload.duplicate(true),
        })

class StubQARunner:
    extends RefCounted

    signal log_emitted(line: String)

    var logs := [
        "Running suite: QA stub",
        "Suite summary: 3 passed, 0 failed, 3 total.",
        "ALL TESTS PASSED",
    ]

    func run_manifest(manifest_path: String, yield_frames: bool = false) -> Dictionary:
        for line in logs:
            emit_signal("log_emitted", line)
        return {
            "exit_code": 0,
            "aggregate_total": 3,
            "aggregate_passed": 3,
            "aggregate_failed": 0,
            "suite_total": 3,
            "suite_passed": 3,
            "suite_failed": 0,
            "diagnostic_total": 0,
            "diagnostic_passed": 0,
            "diagnostic_failed": 0,
            "overall_success": true,
            "logs": PackedStringArray(logs),
        }

    func run_single_diagnostic(diagnostic_id: String, yield_frames: bool = false) -> Dictionary:
        emit_signal("log_emitted", "Running diagnostic: %s" % diagnostic_id)
        return {
            "exit_code": 0,
            "diagnostic_id": diagnostic_id,
            "overall_success": true,
            "logs": PackedStringArray(["Running diagnostic: %s" % diagnostic_id, "DIAGNOSTIC PASSED"]),
        }
