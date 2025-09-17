extends RefCounted

const RNGManager := preload("res://autoloads/RNGManager.gd")

const STREAM_NAMES := ["alpha", "beta", "gamma"]
const MASTER_SEED := 321987
const RESUME_ITERATIONS := 3
const SAMPLE_ITERATIONS := 5

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("deterministic_streams", func(): return _test_deterministic_streams())
    _run_test("save_and_load_roundtrip", func(): return _test_save_and_load_roundtrip())
    _run_test("malformed_payloads", func(): return _test_malformed_payloads())

    return {
        "id": "autoload_rng_manager",
        "suite": "autoload_rng_manager",
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

func _test_deterministic_streams() -> Variant:
    var manager_a := RNGManager.new()
    var manager_b := RNGManager.new()
    manager_a.set_master_seed(MASTER_SEED)
    manager_b.set_master_seed(MASTER_SEED)

    var sequences_a := {}
    var sequences_b := {}

    for stream_name in STREAM_NAMES:
        sequences_a[stream_name] = _collect_sequence(manager_a.get_rng(stream_name), SAMPLE_ITERATIONS)
        sequences_b[stream_name] = _collect_sequence(manager_b.get_rng(stream_name), SAMPLE_ITERATIONS)

    for stream_name in STREAM_NAMES:
        var seq_a: Array = sequences_a[stream_name]
        var seq_b: Array = sequences_b[stream_name]
        if seq_a.size() != SAMPLE_ITERATIONS or seq_b.size() != SAMPLE_ITERATIONS:
            return "Expected deterministic sequences of consistent length for stream '%s'." % stream_name
        for index in SAMPLE_ITERATIONS:
            if seq_a[index] != seq_b[index]:
                return "Deterministic reproduction failed for stream '%s' at iteration %d (expected %d, received %d)." % [stream_name, index, seq_a[index], seq_b[index]]

    return null

func _test_save_and_load_roundtrip() -> Variant:
    var manager := RNGManager.new()
    manager.set_master_seed(MASTER_SEED)

    for stream_name in STREAM_NAMES:
        _collect_sequence(manager.get_rng(stream_name), SAMPLE_ITERATIONS)

    var saved_state := manager.save_state()

    var control := RNGManager.new()
    control.set_master_seed(MASTER_SEED)
    for stream_name in STREAM_NAMES:
        _collect_sequence(control.get_rng(stream_name), SAMPLE_ITERATIONS)

    var expected_resume := {}
    for stream_name in STREAM_NAMES:
        expected_resume[stream_name] = _collect_sequence(control.get_rng(stream_name), RESUME_ITERATIONS)

    for stream_name in STREAM_NAMES:
        manager.get_rng(stream_name).randi()

    manager.load_state(saved_state)

    for stream_name in STREAM_NAMES:
        var rng := manager.get_rng(stream_name)
        var expected: Array = expected_resume[stream_name]
        for index in RESUME_ITERATIONS:
            var value := rng.randi()
            if value != expected[index]:
                return "Stream '%s' expected resume value %d at iteration %d but received %d." % [stream_name, expected[index], index, value]

    var restored_state := manager.save_state()
    if restored_state.get("master_seed", null) != MASTER_SEED:
        return "Round-trip load must restore the master seed to %d." % MASTER_SEED

    var streams := restored_state.get("streams", null)
    if streams == null or typeof(streams) != TYPE_DICTIONARY:
        return "Round-trip save should produce a dictionary of stream payloads."

    for stream_name in STREAM_NAMES:
        if not streams.has(stream_name):
            return "Serialized state missing stream '%s' after round-trip." % stream_name
        var payload = streams[stream_name]
        if typeof(payload) != TYPE_DICTIONARY:
            return "Stream '%s' payload must be a dictionary." % stream_name
        if not payload.has("seed") or not payload.has("state"):
            return "Stream '%s' payload should include seed and state values." % stream_name

    return null

func _test_malformed_payloads() -> Variant:
    var manager := RNGManager.new()
    manager.set_master_seed(MASTER_SEED)
    var rng_alpha := manager.get_rng("alpha")
    rng_alpha.randi()
    var baseline_state := manager.save_state()
    var baseline_streams := baseline_state.get("streams", {})

    manager.load_state(null)
    var state_after_null := manager.save_state()
    if state_after_null.get("master_seed", null) != baseline_state.get("master_seed", null):
        return "Loading null payload should leave the master seed unchanged."
    if state_after_null.get("streams", {}).size() != baseline_streams.size():
        return "Loading null payload should leave the existing streams untouched."

    manager.load_state({})
    var state_after_empty := manager.save_state()
    if state_after_empty.get("master_seed", null) != MASTER_SEED:
        return "Missing master seed payload should preserve the existing master seed."

    var invalid_streams_state := {
        "master_seed": MASTER_SEED + 1,
        "streams": [],
    }
    manager.load_state(invalid_streams_state)

    var comparison := RNGManager.new()
    comparison.set_master_seed(MASTER_SEED + 1)
    var comparison_value := comparison.get_rng("alpha").randi()
    var current_value := manager.get_rng("alpha").randi()
    if current_value != comparison_value:
        return "Invalid streams array should still re-seed existing streams using the provided master seed."

    manager.set_master_seed(MASTER_SEED)
    var malformed_payload := {
        "master_seed": MASTER_SEED,
        "streams": {
            "alpha": "invalid",
            "beta": {
                "seed": 42,
                "state": 99,
            },
        },
    }
    manager.load_state(malformed_payload)

    var alpha_after := manager.get_rng("alpha").randi()
    var expected_alpha_after := RNGManager.new()
    expected_alpha_after.set_master_seed(MASTER_SEED)
    var expected_alpha_value := expected_alpha_after.get_rng("alpha").randi()
    if alpha_after != expected_alpha_value:
        return "Malformed stream payload should skip updates without corrupting other streams."

    var beta_rng := manager.get_rng("beta")
    if beta_rng.seed != 42 or beta_rng.state != 99:
        return "Valid stream payloads should apply seed and state overrides."

    return null

func _collect_sequence(rng: RandomNumberGenerator, count: int) -> Array:
    var values: Array = []
    for i in count:
        values.append(rng.randi())
    return values

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()
