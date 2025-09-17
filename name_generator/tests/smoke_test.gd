extends SceneTree

## Lightweight checks that verify deterministic helpers behave as expected.
func _init():
    _run_array_utils_tests()
    print("Smoke tests completed successfully.")
    quit()

func _run_array_utils_tests() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 1337

    var items := ["alfa", "bravo", "charlie"]
    var pick := ArrayUtils.pick_random_deterministic(items, rng)
    assert(items.has(pick))

    var fallback_state := ArrayUtils.handle_empty_with_fallback([], "fallback", "Test Collection")
    assert(fallback_state["was_empty"] == true)
    assert(fallback_state["value"] == "fallback")

    var weighted := [
        {"value": "heavy", "weight": 3.0},
        {"value": "light", "weight": 1.0},
    ]
    rng.seed = 42
    var weighted_pick := ArrayUtils.pick_weighted_random_deterministic(weighted, rng)
    assert(weighted_pick == "heavy" or weighted_pick == "light")
