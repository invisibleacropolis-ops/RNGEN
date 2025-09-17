extends RefCounted

const RNGProcessorScript := preload("res://name_generator/RNGProcessor.gd")
const NameGeneratorScript := preload("res://name_generator/NameGenerator.gd")
const DebugRNGScript := preload("res://name_generator/tools/DebugRNG.gd")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("signal_lifecycle", func(): return _test_signal_lifecycle())
    _run_test("missing_singleton_fallback", func(): return _test_missing_singleton_fallback())
    _run_test("metadata_stream_resolution", func(): return _test_metadata_stream_resolution())
    _run_test("debug_rng_forwarding", func(): return _test_debug_rng_forwarding())

    return {
        "id": "rng_processor",
        "suite": "rng_processor",
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

func _test_signal_lifecycle() -> Variant:
    var stub_generator := StubNameGenerator.new()
    stub_generator.next_result = "generated_value"
    var stub_manager := StubRNGManager.new()

    return _with_engine_singletons(stub_generator, stub_manager, func():
        var processor := RNGProcessorScript.new()
        processor._ready()

        var started_events: Array = []
        var completed_events: Array = []
        var failed_events: Array = []

        processor.connect("generation_started", Callable(self, "_capture_started").bind(started_events))
        processor.connect("generation_completed", Callable(self, "_capture_completed").bind(completed_events))
        processor.connect("generation_failed", Callable(self, "_capture_failed").bind(failed_events))

        var config := {
            "strategy": "alpha",
            "seed": 7,
        }
        var result := processor.generate(config)

        var error_message := _assert_equal("generated_value", result, "Successful generation should return stubbed value.")
        error_message = error_message or _assert_equal(1, started_events.size(), "generation_started should fire once on success.")
        error_message = error_message or _assert_equal(1, completed_events.size(), "generation_completed should fire once on success.")
        error_message = error_message or _assert_equal(0, failed_events.size(), "generation_failed should not fire on success.")

        if error_message == null:
            var metadata: Dictionary = started_events[0]["metadata"]
            error_message = error_message or _assert_equal("alpha", metadata.get("strategy_id"), "Metadata should capture normalized strategy identifier.")
            error_message = error_message or _assert_equal(7, metadata.get("seed"), "Metadata should expose provided seed.")
            error_message = error_message or _assert_equal("alpha::7", metadata.get("rng_stream"), "Metadata should report seed-derived stream name.")

            var completed_payload: Dictionary = completed_events[0]
            error_message = error_message or _assert_equal("generated_value", completed_payload.get("result", null), "Completion payload should include generator result.")

        started_events.clear()
        completed_events.clear()
        failed_events.clear()

        stub_generator.next_error = {
            "code": "intentional_failure",
            "message": "stub",
        }

        var failure := processor.generate(config)

        error_message = error_message or _assert_true(failure is Dictionary, "Failure path should return error dictionary.")
        if error_message == null and failure is Dictionary:
            error_message = error_message or _assert_equal("intentional_failure", failure.get("code", ""), "Failure payload should echo stubbed error code.")

        error_message = error_message or _assert_equal(1, started_events.size(), "generation_started should fire even when the generator fails.")
        error_message = error_message or _assert_equal(0, completed_events.size(), "generation_completed should not fire for generator failures.")
        error_message = error_message or _assert_equal(1, failed_events.size(), "generation_failed should fire for generator failures.")

        if error_message == null:
            var failure_payload: Dictionary = failed_events[0]
            var error: Dictionary = failure_payload.get("error", {})
            error_message = error_message or _assert_equal("intentional_failure", error.get("code", ""), "generation_failed payload should forward error code.")
            var failed_metadata: Dictionary = failure_payload.get("metadata", {})
            error_message = error_message or _assert_equal("alpha::7", failed_metadata.get("rng_stream", ""), "Failed metadata should reuse derived stream name.")

        processor.free()
        return error_message
    )

func _test_missing_singleton_fallback() -> Variant:
    return _with_engine_singletons(null, null, func():
        var processor := RNGProcessorScript.new()
        processor._ready()

        var started_events: Array = []
        var failed_events: Array = []

        processor.connect("generation_started", Callable(self, "_capture_started").bind(started_events))
        processor.connect("generation_failed", Callable(self, "_capture_failed").bind(failed_events))

        processor.initialize_master_seed(1337)
        var master_seed := processor.get_master_seed()
        var error_message := _assert_equal(1337, master_seed, "Fallback master seed should be preserved without RNGManager.")

        var fallback_rng := processor.get_rng("beta")
        error_message = error_message or _assert_true(fallback_rng is RandomNumberGenerator, "Fallback RNG should create RandomNumberGenerator instances.")
        if error_message == null and fallback_rng is RandomNumberGenerator:
            var repeat_rng := processor.get_rng("beta")
            error_message = error_message or _assert_true(fallback_rng == repeat_rng, "Fallback RNG streams should be memoized per name.")

        var config := {"strategy": "beta"}
        var outcome := processor.generate(config)
        error_message = error_message or _assert_true(outcome is Dictionary, "Missing generator should return diagnostic error dictionary.")
        if error_message == null and outcome is Dictionary:
            error_message = error_message or _assert_equal("missing_name_generator", outcome.get("code", ""), "Processor should surface missing generator error code.")

        error_message = error_message or _assert_equal(0, started_events.size(), "generation_started should not fire when generator singleton is missing.")
        error_message = error_message or _assert_equal(1, failed_events.size(), "generation_failed should fire when generator singleton is missing.")

        if error_message == null:
            var failure_payload: Dictionary = failed_events[0]
            var metadata: Dictionary = failure_payload.get("metadata", {})
            error_message = error_message or _assert_equal("beta", metadata.get("strategy_id", ""), "Metadata should record requested strategy even without generator.")
            error_message = error_message or _assert_equal("%s::beta" % NameGeneratorScript.DEFAULT_STREAM_PREFIX, metadata.get("rng_stream", ""), "Fallback metadata should derive default stream prefix.")

        processor.free()
        return error_message
    )

func _test_metadata_stream_resolution() -> Variant:
    var processor := RNGProcessorScript.new()

    var explicit := processor._build_generation_metadata({
        "strategy": "gamma",
        "seed": 42,
        "rng_stream": "custom_stream",
    }, null)
    var error_message := _assert_equal("custom_stream", explicit.get("rng_stream", ""), "Explicit rng_stream overrides should pass through.")
    error_message = error_message or _assert_equal("gamma", explicit.get("strategy_id", ""), "Strategy identifier should be normalized in metadata.")

    var seeded := processor._build_generation_metadata({
        "strategy": "gamma",
        "seed": " 314 ",
    }, null)
    error_message = error_message or _assert_equal("gamma::314", seeded.get("rng_stream", ""), "Seed-derived streams should use normalized seed text.")

    var defaulted := processor._build_generation_metadata({
        "strategy": "gamma",
    }, null)
    error_message = error_message or _assert_equal("%s::gamma" % NameGeneratorScript.DEFAULT_STREAM_PREFIX, defaulted.get("rng_stream", ""), "Default metadata should prefix streams with NameGenerator default.")

    processor.free()
    return error_message

func _test_debug_rng_forwarding() -> Variant:
    var stub_generator := StubNameGenerator.new()
    stub_generator.next_result = "ok"
    var stub_manager := StubRNGManager.new()
    var debug := StubDebugRNG.new()

    return _with_engine_singletons(stub_generator, stub_manager, func():
        var processor := RNGProcessorScript.new()
        processor._ready()

        processor.set_debug_rng(debug)

        var error_message := _assert_equal(1, debug.attach_calls.size(), "Debug RNG should attach to processor when registered.")
        if error_message == null:
            var attach_payload: Dictionary = debug.attach_calls[0]
            error_message = error_message or _assert_true(attach_payload.get("processor", null) == processor, "Debug RNG should receive processor reference during attach.")
            error_message = error_message or _assert_equal(false, attach_payload.get("propagate", true), "Processor should request non-propagating attach when wiring DebugRNG.")

        error_message = error_message or _assert_equal(1, stub_generator.debug_rngs.size(), "Debug RNG should propagate to NameGenerator singleton.")
        if error_message == null:
            error_message = error_message or _assert_true(stub_generator.debug_rngs[0] == debug, "NameGenerator should receive the DebugRNG instance.")

        var config := {
            "strategy": "delta",
            "seed": 99,
        }
        var result := processor.generate(config)
        error_message = error_message or _assert_equal("ok", result, "Processor should forward generation call to NameGenerator stub.")

        error_message = error_message or _assert_equal(1, debug.stream_records.size(), "Debug RNG should record derived stream usage.")
        if error_message == null and debug.stream_records.size() > 0:
            var record: Dictionary = debug.stream_records[0]
            error_message = error_message or _assert_equal("delta::99", record.get("stream", ""), "Debug RNG should receive seed-derived stream name.")
            var context: Dictionary = record.get("context", {})
            error_message = error_message or _assert_equal("delta", context.get("strategy_id", ""), "Stream usage context should include strategy identifier.")
            error_message = error_message or _assert_equal(99, context.get("seed", null), "Stream usage context should include seed value.")
            error_message = error_message or _assert_equal("seed_derived", context.get("source", ""), "Stream usage context should identify derivation source.")

        processor.set_debug_rng(null)
        error_message = error_message or _assert_equal(1, debug.detach_calls.size(), "Clearing debug RNG should detach from processor.")

        processor.free()
        return error_message
    )

func _capture_started(store: Array, config: Dictionary, metadata: Dictionary) -> void:
    store.append({
        "config": _duplicate_variant(config),
        "metadata": _duplicate_variant(metadata),
    })

func _capture_completed(store: Array, config: Dictionary, result: Variant, metadata: Dictionary) -> void:
    store.append({
        "config": _duplicate_variant(config),
        "result": _duplicate_variant(result),
        "metadata": _duplicate_variant(metadata),
    })

func _capture_failed(store: Array, config: Dictionary, error: Dictionary, metadata: Dictionary) -> void:
    store.append({
        "config": _duplicate_variant(config),
        "error": _duplicate_variant(error),
        "metadata": _duplicate_variant(metadata),
    })

func _assert_equal(expected: Variant, received: Variant, message: String) -> Variant:
    if expected == received:
        return null
    return "%s (expected %s, received %s)" % [message, expected, received]

func _assert_true(condition: bool, message: String) -> Variant:
    if condition:
        return null
    return message

func _with_engine_singletons(generator: Variant, manager: Variant, callable: Callable) -> Variant:
    var original_has: Callable = Engine.has_singleton
    var original_get: Callable = Engine.get_singleton

    Engine.has_singleton = func(name: String) -> bool:
        if name == "NameGenerator":
            return generator != null
        if name == "RNGManager":
            return manager != null
        return original_has.call(name)

    Engine.get_singleton = func(name: String) -> Variant:
        if name == "NameGenerator":
            return generator
        if name == "RNGManager":
            return manager
        return original_get.call(name)

    var result = callable.call()

    Engine.has_singleton = original_has
    Engine.get_singleton = original_get

    return result

func _duplicate_variant(value: Variant) -> Variant:
    if value is Dictionary:
        return (value as Dictionary).duplicate(true)
    if value is Array:
        return (value as Array).duplicate(true)
    return value

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

class StubNameGenerator:
    extends RefCounted

    var next_result: Variant = null
    var next_error: Variant = null
    var generate_calls: Array[Dictionary] = []
    var debug_rngs: Array = []

    func generate(config: Variant, override_rng: RandomNumberGenerator = null) -> Variant:
        var config_copy := config
        if config is Dictionary:
            config_copy = (config as Dictionary).duplicate(true)
        elif config is Array:
            config_copy = (config as Array).duplicate(true)
        generate_calls.append({
            "config": config_copy,
            "override_rng": override_rng,
        })
        if next_error != null:
            var payload := next_error
            next_error = null
            return payload
        return next_result

    func set_debug_rng(debug_rng: Variant) -> void:
        debug_rngs.append(debug_rng)

class StubRNGManager:
    extends RefCounted

    var master_seed: int = 0
    var requested_streams: Array = []

    func set_master_seed(value: int) -> void:
        master_seed = value

    func get_master_seed() -> int:
        return master_seed

    func get_rng(stream_name: String) -> RandomNumberGenerator:
        requested_streams.append(stream_name)
        var rng := RandomNumberGenerator.new()
        var seed_value := int(hash("%s::%s" % [master_seed, stream_name]) & 0x7fffffffffffffff)
        rng.seed = seed_value
        rng.state = seed_value
        return rng

class StubDebugRNG:
    extends RefCounted

    var attach_calls: Array = []
    var detach_calls: Array = []
    var stream_records: Array = []

    func attach_to_processor(processor: Object, log_path: String = DebugRNGScript.DEFAULT_LOG_PATH, propagate: bool = true) -> void:
        attach_calls.append({
            "processor": processor,
            "log_path": log_path,
            "propagate": propagate,
        })

    func detach_from_processor(processor: Object) -> void:
        detach_calls.append(processor)

    func record_stream_usage(stream_name: String, context: Dictionary = {}) -> void:
        var context_copy := context
        if context is Dictionary:
            context_copy = (context as Dictionary).duplicate(true)
        stream_records.append({
            "stream": stream_name,
            "context": context_copy,
        })
