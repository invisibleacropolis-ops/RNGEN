extends RefCounted

const NameGenerator := preload("res://name_generator/NameGenerator.gd")

class StubRNGManager:
    var rngs: Dictionary = {}
    var requests: Array[String] = []

    func get_rng(stream_name: String) -> RandomNumberGenerator:
        requests.append(stream_name)
        if not rngs.has(stream_name):
            var rng := RandomNumberGenerator.new()
            var hashed := String(stream_name).hash()
            rng.seed = int(abs(hashed))
            rngs[stream_name] = rng
        return rngs[stream_name]

class TrackingDebugRNG:
    var stream_records: Array[Dictionary] = []

    func track_strategy(_identifier: String, _strategy: Variant) -> void:
        pass

    func untrack_strategy(_strategy: Variant) -> void:
        pass

    func clear_tracked_strategies() -> void:
        stream_records.clear()

    func record_stream_usage(stream_name: String, context: Dictionary) -> void:
        var entry := {
            "stream_name": stream_name,
            "context": context.duplicate(true) if context is Dictionary else {},
        }
        stream_records.append(entry)

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

    _run_test("registers_builtin_strategies", func(): _test_registers_builtin_strategies())
    _run_test("generate_respects_override_rng", func(): _test_generate_with_override_rng())
    _run_test("generate_uses_seeded_streams", func(): _test_generate_with_seeded_stream())
    _run_test("generate_reports_missing_strategy", func(): _test_missing_strategy_error())
    _run_test("generate_reports_invalid_stream_name", func(): _test_invalid_stream_name_error())
    _run_test("generate_records_fallback_usage", func(): _test_fallback_rng_recording())

    return {
        "suite": "NameGeneratorDiagnostic",
        "id": "name_generator",
        "total": _total,
        "passed": _passed,
        "failed": _failed,
        "failures": _failures.duplicate(true),
    }

func _run_test(name: String, callable: Callable) -> void:
    _total += 1
    var error_message := ""
    var success := true

    var result = callable.call()
    if result != null:
        success = false
        error_message = String(result)

    if success:
        _passed += 1
    else:
        _failed += 1
        _failures.append({
            "name": name,
            "message": error_message,
        })

func _test_registers_builtin_strategies() -> Variant:
    return _with_engine_stub(null, func(_stub_manager = null):
        var generator := _create_generator()
        var identifiers := generator.list_strategies()
        var expected := PackedStringArray([
            "hybrid",
            "markov",
            "syllable",
            "template",
            "wordlist",
        ])
        if identifiers != expected:
            return "Expected strategies %s but received %s" % [expected, identifiers]

        var description := generator.describe_strategy("wordlist")
        if description.is_empty():
            return "describe_strategy should produce metadata for registered strategies."
        if description.get("id", "") != "wordlist":
            return "Strategy description should include the identifier."
        if String(description.get("display_name", "")).is_empty():
            return "Strategy description should include a display name."

        var expected_config := description.get("expected_config", {})
        if not (expected_config is Dictionary):
            return "Strategy descriptions must include an expected_config dictionary."
        var required := expected_config.get("required", PackedStringArray())
        if typeof(required) != TYPE_PACKED_STRING_ARRAY:
            return "expected_config.required should be a PackedStringArray."
        if not required.has("wordlist_paths"):
            return "expected_config.required should mention the wordlist_paths key."

        generator.free()
        return null
    )

func _test_generate_with_override_rng() -> Variant:
    var config := {
        "strategy": "wordlist",
        "wordlist_paths": ["res://tests/test_assets/wordlist_basic.tres"],
    }

    var first := _with_engine_stub(null, func(_stub_manager = null):
        var generator := _create_generator()
        var rng := RandomNumberGenerator.new()
        rng.seed = 2024
        var value := generator.generate(config, rng)
        generator.free()
        return value
    )

    var second := _with_engine_stub(null, func(_stub_manager = null):
        var generator := _create_generator()
        var rng := RandomNumberGenerator.new()
        rng.seed = 2024
        var value := generator.generate(config, rng)
        generator.free()
        return value
    )

    if first is Dictionary:
        return "Override RNG run returned error: %s" % first
    if second is Dictionary:
        return "Override RNG run returned error: %s" % second
    if first != second:
        return "Providing the same seeded RNG should yield deterministic results."

    return null

func _test_generate_with_seeded_stream() -> Variant:
    var config := {
        "strategy": "wordlist",
        "wordlist_paths": ["res://tests/test_assets/wordlist_basic.tres"],
        "seed": "diagnostic",
    }

    var first := _with_engine_stub(StubRNGManager.new(), func(_stub_manager = null):
        var generator := _create_generator()
        var value := generator.generate(config)
        generator.free()
        return value
    )

    var second := _with_engine_stub(StubRNGManager.new(), func(_stub_manager = null):
        var generator := _create_generator()
        var value := generator.generate(config)
        generator.free()
        return value
    )

    if first is Dictionary:
        return "Seeded stream run returned error: %s" % first
    if second is Dictionary:
        return "Seeded stream run returned error: %s" % second
    if first != second:
        return "Stream-derived seeds should reproduce results across runs."

    return null

func _test_missing_strategy_error() -> Variant:
    var result := _with_engine_stub(null, func(_stub_manager = null):
        var generator := _create_generator()
        var response := generator.generate({})
        generator.free()
        return response
    )

    if not (result is Dictionary):
        return "Missing strategy should return an error dictionary."
    if result.get("code", "") != "missing_strategy":
        return "Unexpected error code for missing strategy: %s" % result

    return null

func _test_invalid_stream_name_error() -> Variant:
    var config := {
        "strategy": "wordlist",
        "wordlist_paths": ["res://tests/test_assets/wordlist_basic.tres"],
        "seed": "valid",
        "rng_stream": 42,
    }

    var result := _with_engine_stub(null, func(_stub_manager = null):
        var generator := _create_generator()
        var response := generator.generate(config)
        generator.free()
        return response
    )

    if not (result is Dictionary):
        return "Invalid stream name should return an error dictionary."
    if result.get("code", "") != "invalid_stream_name":
        return "Unexpected error code for invalid stream name: %s" % result

    return null

func _test_fallback_rng_recording() -> Variant:
    var debug := TrackingDebugRNG.new()
    var config := {
        "strategy": "wordlist",
        "wordlist_paths": ["res://tests/test_assets/wordlist_basic.tres"],
    }

    var result := _with_engine_stub(null, func(_stub_manager = null):
        var generator := _create_generator()
        generator.set_debug_rng(debug)
        var value := generator.generate(config)
        generator.free()
        return value
    )

    if result is Dictionary:
        return "Fallback RNG run returned error: %s" % result

    var recorded_fallback := false
    for entry in debug.stream_records:
        var context: Dictionary = entry.get("context", {})
        if context.get("source", "") == "fallback_rng_randomize":
            recorded_fallback = true
            break

    if not recorded_fallback:
        return "Fallback RNG usage should be recorded by the debug tracker."

    return null

func _create_generator() -> NameGenerator:
    var generator := NameGenerator.new()
    generator._ready()
    return generator

func _with_engine_stub(stub_manager: Variant, callable: Callable) -> Variant:
    var original_has: Callable = Engine.has_singleton
    var original_get: Callable = Engine.get_singleton

    Engine.has_singleton = func(name: String) -> bool:
        if name == "RNGManager":
            return stub_manager != null
        return original_has.call(name)

    Engine.get_singleton = func(name: String) -> Variant:
        if name == "RNGManager":
            return stub_manager
        return original_get.call(name)

    var outcome = callable.call(stub_manager)

    Engine.has_singleton = original_has
    Engine.get_singleton = original_get

    return outcome
