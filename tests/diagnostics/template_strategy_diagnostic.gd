extends RefCounted

const TemplateStrategy := preload("res://name_generator/strategies/TemplateStrategy.gd")
const GeneratorStrategy := preload("res://name_generator/strategies/GeneratorStrategy.gd")
const RNGStreamRouter := preload("res://name_generator/utils/RNGManager.gd")

class StubRNGProcessor:
    var responses: Dictionary = {}
    var invocations: Array[Dictionary] = []

    func reset(definitions_only: bool = false) -> void:
        if not definitions_only:
            responses.clear()
        invocations.clear()

    func define_response(stub_id: String, response: Variant) -> void:
        responses[stub_id] = response

    func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
        var stub_id := String(config.get("stub_id", ""))
        var record := {
            "stub_id": stub_id,
            "config": config.duplicate(true),
            "seed": String(config.get("seed", "")),
            "rng_seed": int(rng.seed),
        }
        invocations.append(record)

        if responses.has(stub_id):
            var entry := responses[stub_id]
            if entry is Callable:
                return (entry as Callable).call(config, rng)
            return entry

        if stub_id != "":
            return "%s::%s" % [stub_id, record["seed"]]
        return "__stub_missing__"

    func get_invocations_for(stub_id: String) -> Array[Dictionary]:
        var matches: Array[Dictionary] = []
        for record in invocations:
            if record.get("stub_id", "") == stub_id:
                matches.append(record)
        return matches

var _strategy: TemplateStrategy
var _stub_processor: StubRNGProcessor
var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _strategy = TemplateStrategy.new()
    _stub_processor = StubRNGProcessor.new()
    _checks.clear()

    _record("template_expansion", func(): return _test_template_expansion())
    _record("occurrence_specific_seeding", func(): return _test_occurrence_specific_seeding())
    _record("recursion_depth_enforcement", func(): return _test_recursion_depth_enforcement())
    _record("error_invalid_template_type", func(): return _test_invalid_template_type())
    _record("error_invalid_sub_generators_type", func(): return _test_invalid_sub_generators_type())
    _record("error_missing_template_token", func(): return _test_missing_template_token())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    return {
        "id": "template_strategy",
        "suite": "template_strategy",
        "name": "Template strategy deterministic harness",
        "total": _checks.size(),
        "passed": _checks.size() - failures.size(),
        "failed": failures.size(),
        "failures": failures.duplicate(true),
    }

func _record(name: String, callable: Callable) -> void:
    var message = callable.call()
    var success := message == null
    _checks.append({
        "name": name,
        "success": success,
        "message": "" if success else String(message),
    })

func _with_stubbed_processor(callable: Callable) -> Variant:
    var original_has := Engine.has_singleton
    var original_get := Engine.get_singleton

    Engine.has_singleton = func(name: String) -> bool:
        if name == "RNGProcessor":
            return true
        return original_has.call(name)

    Engine.get_singleton = func(name: String) -> Variant:
        if name == "RNGProcessor":
            return _stub_processor
        return original_get.call(name)

    var result = callable.call()

    Engine.has_singleton = original_has
    Engine.get_singleton = original_get

    return result

func _make_rng(seed: int) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed
    rng.state = seed
    return rng

func _test_template_expansion() -> Variant:
    _stub_processor.reset()
    _stub_processor.define_response("greeting", "Hello")
    _stub_processor.define_response("subject", "world")

    var rng := _make_rng(12345)
    var config := {
        "template_string": "[greeting], [subject]!",
        "sub_generators": {
            "greeting": {"stub_id": "greeting"},
            "subject": {"stub_id": "subject"},
        },
        "seed": "expansion",
    }

    var result := _with_stubbed_processor(func():
        return _strategy.generate(config, rng)
    )

    if result is GeneratorStrategy.GeneratorError:
        return "Expected template expansion to succeed but received error %s" % [result.code]

    if String(result) != "Hello, world!":
        return "Expanded template produced unexpected output: %s" % [result]

    var invocation_order := []
    for record in _stub_processor.invocations:
        invocation_order.append(record.get("stub_id", ""))

    if invocation_order != ["greeting", "subject"]:
        return "Template should request sub-generators in order; received %s" % [invocation_order]

    return null

func _test_occurrence_specific_seeding() -> Variant:
    _stub_processor.reset()

    var rng := _make_rng(24680)
    var parent_seed := "occurrence"
    var config := {
        "template_string": "[item]-[item]-[item]",
        "sub_generators": {
            "item": {"stub_id": "item"},
        },
        "seed": parent_seed,
    }

    var result := _with_stubbed_processor(func():
        return _strategy.generate(config, rng)
    )

    if result is GeneratorStrategy.GeneratorError:
        return "Occurrence test returned error: %s" % [result.code]

    var invocations := _stub_processor.get_invocations_for("item")
    if invocations.size() != 3:
        return "Expected three sub-generator invocations, received %d" % invocations.size()

    var expected_seeds := [
        "%s::item::0" % parent_seed,
        "%s::item::1" % parent_seed,
        "%s::item::2" % parent_seed,
    ]

    for index in range(invocations.size()):
        var actual_seed := String(invocations[index].get("seed", ""))
        if actual_seed != expected_seeds[index]:
            return "Occurrence %d received seed %s instead of %s" % [index, actual_seed, expected_seeds[index]]

    var router := RNGStreamRouter.new(rng.seed)
    for index in range(invocations.size()):
        var derived_rng := router.derive_rng(["item", String(index), String(1)])
        var recorded_seed := int(invocations[index].get("rng_seed", -1))
        if recorded_seed != int(derived_rng.seed):
            return "Occurrence %d used RNG seed %d but expected %d" % [index, recorded_seed, int(derived_rng.seed)]

    return null

func _test_recursion_depth_enforcement() -> Variant:
    _stub_processor.reset()

    var rng := _make_rng(9876)
    var config := {
        "template_string": "[loop]",
        "sub_generators": {
            "loop": {"stub_id": "loop"},
        },
        "max_depth": 1,
        "__template_depth": 1,
    }

    var result := _with_stubbed_processor(func():
        return _strategy.generate(config, rng)
    )

    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected recursion guard to return an error, received %s" % [result]

    if result.code != "template_recursion_depth_exceeded":
        return "Unexpected error code for recursion guard: %s" % [result.code]

    if String(result.message) != "Template expansion exceeded the allowed recursion depth.":
        return "Recursion guard returned unexpected message: %s" % [result.message]

    var details := result.details
    if int(details.get("max_depth", 0)) != 1 or int(details.get("current_depth", 0)) != 1:
        return "Recursion guard should expose max_depth and current_depth details."

    if not _stub_processor.invocations.is_empty():
        return "Recursion guard should prevent sub-generator invocations."

    return null

func _test_invalid_template_type() -> Variant:
    var rng := _make_rng(13579)
    var config := {
        "template_string": 42,
        "sub_generators": {},
    }

    var result := _with_stubbed_processor(func():
        return _strategy.generate(config, rng)
    )

    if not (result is GeneratorStrategy.GeneratorError):
        return "Invalid template type should return an error."

    if result.code != "invalid_template_type":
        return "Unexpected code for invalid template type: %s" % [result.code]

    if String(result.message) != "TemplateStrategy requires 'template_string' to be a String.":
        return "Unexpected message for invalid template type: %s" % [result.message]

    return null

func _test_invalid_sub_generators_type() -> Variant:
    var rng := _make_rng(112233)
    var config := {
        "template_string": "[token]",
        "sub_generators": ["not", "a", "dictionary"],
    }

    var result := _with_stubbed_processor(func():
        return _strategy.generate(config, rng)
    )

    if not (result is GeneratorStrategy.GeneratorError):
        return "Invalid sub_generators type should return an error."

    if result.code != "invalid_sub_generators_type":
        return "Unexpected code for invalid sub_generators type: %s" % [result.code]

    if String(result.message) != "TemplateStrategy optional 'sub_generators' must be a Dictionary.":
        return "Unexpected message for invalid sub_generators type: %s" % [result.message]

    return null

func _test_missing_template_token() -> Variant:
    var rng := _make_rng(998877)
    var config := {
        "template_string": "[unknown]",
        "sub_generators": {},
    }

    var result := _with_stubbed_processor(func():
        return _strategy.generate(config, rng)
    )

    if not (result is GeneratorStrategy.GeneratorError):
        return "Missing template token should return an error."

    if result.code != "missing_template_token":
        return "Unexpected code for missing token: %s" % [result.code]

    if String(result.message) != "Template token 'unknown' does not have a configured sub-generator.":
        return "Unexpected message for missing token: %s" % [result.message]

    var details := result.details
    if String(details.get("token", "")) != "unknown":
        return "Missing token details should include the offending token."

    return null

