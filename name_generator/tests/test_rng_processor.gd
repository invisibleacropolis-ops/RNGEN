extends RefCounted

const RNGProcessor := preload("res://name_generator/RNGProcessor.gd")

const WORDLIST_PATH := "res://tests/test_assets/wordlist_basic.tres"

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

var _started_events: Array[Dictionary] = []
var _completed_events: Array[Dictionary] = []
var _failed_events: Array[Dictionary] = []

func run() -> Dictionary:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

    _run_test("seed_management_controls_master_seed", func(): _test_seed_management())
    _run_test("strategy_introspection_matches_name_generator", func(): _test_strategy_introspection())
    _run_test("generate_emits_success_signals", func(): _test_generate_success())
    _run_test("generate_emits_failure_signals", func(): _test_generate_failure())

    return {
        "suite": "RNGProcessor",
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

func _test_seed_management() -> Variant:
    var processor := _make_processor()
    processor.initialize_master_seed(1337)

    if processor.get_master_seed() != 1337:
        return "Processor must report the master seed set via initialize_master_seed."

    if Engine.has_singleton("RNGManager"):
        var manager := Engine.get_singleton("RNGManager")
        if manager != null and manager.has_method("get_master_seed"):
            if int(manager.call("get_master_seed")) != 1337:
                return "initialize_master_seed should delegate to RNGManager when available."

    var new_seed := processor.reset_master_seed()
    if processor.get_master_seed() != new_seed:
        return "reset_master_seed should return the same value exposed by get_master_seed."

    var rng := processor.get_rng("rng_processor_test_stream")
    if rng == null or not (rng is RandomNumberGenerator):
        return "get_rng must always return a RandomNumberGenerator instance."

    if Engine.has_singleton("RNGManager"):
        var manager_rng := Engine.get_singleton("RNGManager").call("get_rng", "rng_processor_test_stream")
        if manager_rng != rng:
            return "Processor should proxy RNGManager streams when the singleton is present."

    return null

func _test_strategy_introspection() -> Variant:
    var processor := _make_processor()
    var strategies := processor.list_strategies()
    if strategies.is_empty():
        return "Processor should expose at least one registered strategy."

    if Engine.has_singleton("NameGenerator"):
        var generator := Engine.get_singleton("NameGenerator")
        if generator != null and generator.has_method("list_strategies"):
            var generator_list := generator.call("list_strategies")
            if generator_list is PackedStringArray:
                if strategies != generator_list:
                    return "list_strategies must mirror NameGenerator's ordering."
            else:
                var normalized := PackedStringArray()
                for entry in generator_list:
                    normalized.append(String(entry))
                if strategies != normalized:
                    return "list_strategies must mirror NameGenerator's ordering."

    var description := processor.describe_strategy("wordlist")
    if description.is_empty():
        return "describe_strategy should provide metadata for known strategies."

    if not description.has("expected_config"):
        return "Strategy description must include an expected_config payload."

    if not description.has("notes"):
        return "Strategy description must expose human-readable notes."

    var unknown := processor.describe_strategy("does_not_exist")
    if not unknown.is_empty():
        return "Unknown strategies should yield an empty description."

    var all_descriptions := processor.describe_strategies()
    for identifier in strategies:
        if not all_descriptions.has(identifier):
            return "describe_strategies must include every registered strategy."

    return null

func _test_generate_success() -> Variant:
    _reset_signal_captures()
    var processor := _make_processor()
    processor.initialize_master_seed(2024)

    processor.connect("generation_started", Callable(self, "_on_generation_started"))
    processor.connect("generation_completed", Callable(self, "_on_generation_completed"))
    processor.connect("generation_failed", Callable(self, "_on_generation_failed"))

    var config := {
        "strategy": "wordlist",
        "wordlist_paths": [WORDLIST_PATH],
        "seed": "rng_processor_success",
    }

    var result := processor.generate(config)
    if result is Dictionary and result.has("code"):
        return "Successful generation should not surface error dictionaries."

    if _started_events.size() != 1:
        return "generation_started must emit exactly once for a request."

    if _completed_events.size() != 1:
        return "generation_completed must emit for successful requests."

    if not _failed_events.is_empty():
        return "generation_failed should not emit for successful requests."

    var metadata: Dictionary = _started_events[0]["metadata"]
    if metadata.get("strategy_id", "") != "wordlist":
        return "generation_started metadata should capture the normalized strategy id."

    if metadata.get("seed", "") != config["seed"]:
        return "generation_started metadata should expose the resolved seed."

    if metadata.get("rng_stream", "") != "wordlist::rng_processor_success":
        return "generation_started metadata should include the resolved RNG stream name."

    var completed: Dictionary = _completed_events[0]
    if completed.get("result", "") == "":
        return "generation_completed should forward the generation result."

    return null

func _test_generate_failure() -> Variant:
    _reset_signal_captures()
    var processor := _make_processor()
    processor.initialize_master_seed(404)

    processor.connect("generation_started", Callable(self, "_on_generation_started"))
    processor.connect("generation_completed", Callable(self, "_on_generation_completed"))
    processor.connect("generation_failed", Callable(self, "_on_generation_failed"))

    var config := {
        "strategy": "does_not_exist",
        "seed": "rng_processor_failure",
    }

    var expected := Engine.get_singleton("NameGenerator").call("generate", config)
    var result := processor.generate(config)

    if not (result is Dictionary) or result.get("code", "") == "":
        return "Processor should return NameGenerator error dictionaries unchanged."

    if result != expected:
        return "Processor should proxy NameGenerator.generate results verbatim."

    if _started_events.size() != 1:
        return "generation_started must emit even when generation fails."

    if not _completed_events.is_empty():
        return "generation_completed should not emit when generation fails."

    if _failed_events.size() != 1:
        return "generation_failed should emit exactly once for failures."

    var failure: Dictionary = _failed_events[0]
    var metadata: Dictionary = failure.get("metadata", {})
    if metadata.get("strategy_id", "") != "does_not_exist":
        return "generation_failed metadata should include the normalized strategy id."

    if metadata.get("rng_stream", "") != "does_not_exist::rng_processor_failure":
        return "generation_failed metadata should capture the resolved RNG stream."

    var error: Dictionary = failure.get("error", {})
    if error.get("code", "") != "unknown_strategy":
        return "generation_failed should forward the underlying error code."

    return null

func _make_processor() -> RNGProcessor:
    _ensure_required_singletons()
    var processor := RNGProcessor.new()
    processor._ready()
    return processor

func _ensure_required_singletons() -> void:
    if not Engine.has_singleton("RNGManager"):
        var rng_manager_script: GDScript = load("res://name_generator/RNGManager.gd")
        var rng_manager_instance: Node = rng_manager_script.new()
        rng_manager_instance._ready()
        Engine.register_singleton("RNGManager", rng_manager_instance)

    if not Engine.has_singleton("NameGenerator"):
        var name_generator_script: GDScript = load("res://name_generator/NameGenerator.gd")
        var generator_instance: Node = name_generator_script.new()
        generator_instance._ready()
        if generator_instance.has_method("_register_builtin_strategies"):
            generator_instance.call("_register_builtin_strategies")
        Engine.register_singleton("NameGenerator", generator_instance)

func _reset_signal_captures() -> void:
    _started_events.clear()
    _completed_events.clear()
    _failed_events.clear()

func _on_generation_started(config: Dictionary, metadata: Dictionary) -> void:
    _started_events.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
    })

func _on_generation_completed(config: Dictionary, result: Variant, metadata: Dictionary) -> void:
    _completed_events.append({
        "config": config.duplicate(true),
        "result": result,
        "metadata": metadata.duplicate(true),
    })

func _on_generation_failed(config: Dictionary, error: Dictionary, metadata: Dictionary) -> void:
    _failed_events.append({
        "config": config.duplicate(true),
        "error": error.duplicate(true),
        "metadata": metadata.duplicate(true),
    })
