extends RefCounted

const RNGManager := preload("res://name_generator/RNGManager.gd")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("reseed_existing_streams", func(): _test_reseed_existing_streams())
    _run_test("new_streams_use_updated_seed", func(): _test_new_streams_use_updated_seed())

    return {
        "suite": "RNG Manager Seed Reset",
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

func _test_reseed_existing_streams() -> Variant:
    var manager := RNGManager.new()
    manager.set_master_seed(1111)

    var stream_name := "alpha"
    var rng := manager.get_rng(stream_name)

    # Advance the RNG to ensure reseeding replaces the state rather than leaving it untouched.
    _ = rng.randf()

    manager.set_master_seed(2222)

    var expected_seed := manager._compute_stream_seed(stream_name)
    var expected_rng := RandomNumberGenerator.new()
    expected_rng.seed = expected_seed
    expected_rng.state = expected_seed

    var observed_value := rng.randf()
    var expected_value := expected_rng.randf()

    if not is_equal_approx(observed_value, expected_value):
        return "Reseeded RNG stream must align with the value produced by the new master seed."

    if rng.seed != expected_seed or rng.state != rng.seed:
        return "Reseeded RNG stream must expose the updated seed and reset state."

    return null

func _test_new_streams_use_updated_seed() -> Variant:
    var manager := RNGManager.new()
    manager.set_master_seed(7007)

    var initial_rng := manager.get_rng("baseline")
    _ = initial_rng.randf()

    manager.set_master_seed(9090)

    var new_stream_name := "delta"
    var observed_rng := manager.get_rng(new_stream_name)

    var expected_seed := manager._compute_stream_seed(new_stream_name)
    if observed_rng.seed != expected_seed:
        return "Streams created after reseeding must adopt the seed derived from the updated master seed."

    var expected_rng := RandomNumberGenerator.new()
    expected_rng.seed = expected_seed
    expected_rng.state = expected_seed

    var observed_value := observed_rng.randf()
    var expected_value := expected_rng.randf()

    if not is_equal_approx(observed_value, expected_value):
        return "New streams must reproduce the deterministic sequence defined by the updated master seed."

    return null

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()
