extends RefCounted

const ArrayUtils := preload("res://utils/ArrayUtils.gd")

var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _checks.clear()

    _record("pick_uniform_respects_seeded_rng", func(): return _test_pick_uniform_respects_seeded_rng())
    _record("pick_uniform_handles_empty_arrays", func(): return _test_pick_uniform_handles_empty_arrays())
    _record("pick_weighted_respects_seeded_rng", func(): return _test_pick_weighted_respects_seeded_rng())
    _record("pick_weighted_handles_empty_inputs", func(): return _test_pick_weighted_handles_empty_inputs())
    _record("pick_weighted_zero_weights_fall_back_to_uniform", func(): return _test_pick_weighted_zero_weights_fall_back())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    return {
        "id": "utils_array_utils",
        "name": "ArrayUtils deterministic selection diagnostic",
        "total": _checks.size(),
        "passed": _checks.size() - failures.size(),
        "failed": failures.size(),
        "failures": failures.duplicate(true),
    }

func _record(name: String, callable: Callable) -> void:
    var result = callable.call()
    var success := result == null
    _checks.append({
        "name": name,
        "success": success,
        "message": "" if success else String(result),
    })

func _test_pick_uniform_respects_seeded_rng() -> Variant:
    var values := ["alpha", "beta", "gamma", "delta"]

    var first_rng := RandomNumberGenerator.new()
    first_rng.seed = 12345
    var second_rng := RandomNumberGenerator.new()
    second_rng.seed = 12345

    var first_sequence := []
    var second_sequence := []
    for i in range(8):
        first_sequence.append(ArrayUtils.pick_uniform(values, first_rng))
        second_sequence.append(ArrayUtils.pick_uniform(values, second_rng))

    if first_sequence != second_sequence:
        return "Identical seeds must produce matching uniform selections."

    var alternate_rng := RandomNumberGenerator.new()
    alternate_rng.seed = 54321
    var alternate_sequence := []
    for i in range(8):
        alternate_sequence.append(ArrayUtils.pick_uniform(values, alternate_rng))

    if alternate_sequence == first_sequence:
        return "Different seeds should lead to a distinct uniform sequence."

    return null

func _test_pick_uniform_handles_empty_arrays() -> Variant:
    var rng := RandomNumberGenerator.new()
    rng.seed = 98765
    var initial_state := rng.state

    var result := ArrayUtils.pick_uniform([], rng)
    if result != null:
        return "Uniform selection should return null for empty arrays."

    if rng.state != initial_state:
        return "Uniform selection must not advance RNG state when the array is empty."

    return null

func _test_pick_weighted_respects_seeded_rng() -> Variant:
    var values := ["ember", "frost", "gale"]
    var weights := [1.0, 2.5, 5.0]

    var first_rng := RandomNumberGenerator.new()
    first_rng.seed = 2468
    var second_rng := RandomNumberGenerator.new()
    second_rng.seed = 2468

    var first_sequence := []
    var second_sequence := []
    for i in range(8):
        first_sequence.append(ArrayUtils.pick_weighted(values, weights, first_rng))
        second_sequence.append(ArrayUtils.pick_weighted(values, weights, second_rng))

    if first_sequence != second_sequence:
        return "Weighted selection should be deterministic for identical seeds."

    var alternate_rng := RandomNumberGenerator.new()
    alternate_rng.seed = 1357
    var alternate_sequence := []
    for i in range(8):
        alternate_sequence.append(ArrayUtils.pick_weighted(values, weights, alternate_rng))

    if alternate_sequence == first_sequence:
        return "Different seeds should generate a distinct weighted sequence."

    return null

func _test_pick_weighted_handles_empty_inputs() -> Variant:
    var rng := RandomNumberGenerator.new()
    rng.seed = 424242
    var initial_state := rng.state

    var result := ArrayUtils.pick_weighted([], [], rng)
    if result != null:
        return "Weighted selection should return null when values are empty."

    if rng.state != initial_state:
        return "Weighted selection must not change RNG state when no selection occurs."

    return null

func _test_pick_weighted_zero_weights_fall_back() -> Variant:
    var values := ["onyx", "pearl", "quartz", "ruby"]
    var zero_weights := [0.0, 0.0, 0.0, 0.0]

    var weighted_rng := RandomNumberGenerator.new()
    weighted_rng.seed = 112233
    var uniform_rng := RandomNumberGenerator.new()
    uniform_rng.seed = 112233

    var weighted_pick := ArrayUtils.pick_weighted(values, zero_weights, weighted_rng)
    var uniform_pick := ArrayUtils.pick_uniform(values, uniform_rng)

    if weighted_pick != uniform_pick:
        return "Zero-weight selections should defer to uniform picking."

    if weighted_rng.state != uniform_rng.state:
        return "Fallback to uniform should consume RNG state identically."

    return null
