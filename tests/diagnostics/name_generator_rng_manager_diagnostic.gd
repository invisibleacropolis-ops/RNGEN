extends RefCounted

const RNGManager := preload("res://name_generator/RNGManager.gd")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("rng_manager_behaviors", func(): _test_rng_manager_behaviors())
    _run_test("state_restoration_reproduces_sequences", func(): _test_state_restoration_reproduces_sequences())

    return {
        "suite": "Name Generator RNG Manager Diagnostic",
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

func _test_rng_manager_behaviors() -> Variant:
    var manager := RNGManager.new()
    manager.set_master_seed(424242)

    var alpha_rng := manager.get_rng("alpha")
    var alpha_rng_again := manager.get_rng("alpha")
    if alpha_rng != alpha_rng_again:
        return "get_rng must cache streams by name."

    if manager._streams.size() != 1:
        return "Expected exactly one cached stream after repeated access."

    var previous_seed := manager.get_master_seed()
    manager.randomize_master_seed()

    if manager.get_master_seed() == previous_seed:
        return "randomize_master_seed should update the stored master seed."

    if not manager._streams.is_empty():
        return "randomize_master_seed should clear cached streams."

    var default_rng := manager.get_rng("default")
    var empty_name_rng := manager.get_rng("")
    if default_rng != empty_name_rng:
        return "Zero-length stream names should resolve to the 'default' stream."

    var utility_value := manager.randf()
    if utility_value < 0.0 or utility_value >= 1.0:
        return "randf should return a normalized float in [0.0, 1.0)."

    if not manager._streams.has("utility"):
        return "randf helper should create and cache the 'utility' stream."

    var combat_roll := manager.randi_range("combat", 5, 10)
    if combat_roll < 5 or combat_roll > 10:
        return "randi_range helper must respect the inclusive bounds provided."

    if not manager._streams.has("combat"):
        return "randi_range helper should cache the requested stream."

    var state := manager.save_state()
    if not (state is Dictionary):
        return "save_state should return a Dictionary payload."

    if not state.has("master_seed") or not state.has("streams"):
        return "Serialized state must include master_seed and streams entries."

    var streams_payload := state["streams"] if state.has("streams") else null
    if not (streams_payload is Dictionary):
        return "Streams entry in serialized state must be a Dictionary."

    if not streams_payload.has("default"):
        return "Serialized streams should include the mapped 'default' stream for empty names."

    if not streams_payload.has("combat") or not streams_payload.has("utility"):
        return "Serialized state should include all active streams."

    return null

func _test_state_restoration_reproduces_sequences() -> Variant:
    var manager := RNGManager.new()
    manager.set_master_seed(9001)

    manager.get_rng("default")
    manager.get_rng("alpha")
    manager.get_rng("beta")
    manager.get_rng("")
    manager.randf()
    manager.randi_range("loot", 1, 100)

    var saved_state := manager.save_state()

    var mirror := RNGManager.new()
    mirror.load_state(saved_state)

    var expected := {
        "default_randi": mirror.get_rng("default").randi(),
        "alpha_randi": mirror.get_rng("alpha").randi(),
        "beta_randf": mirror.get_rng("beta").randf(),
        "utility_randf": mirror.randf(),
        "loot_range": mirror.randi_range("loot", 1, 100),
    }

    manager.get_rng("default").randi()
    manager.get_rng("alpha").randf()
    manager.get_rng("beta").randi()
    manager.randf()
    manager.randi_range("loot", 1, 100)

    manager.load_state(saved_state)

    if manager.get_rng("default").randi() != expected["default_randi"]:
        return "Reloaded default stream should reproduce the previous integer sequence."

    if manager.get_rng("alpha").randi() != expected["alpha_randi"]:
        return "Reloaded named streams must resume from the serialized state."

    if abs(manager.get_rng("beta").randf() - float(expected["beta_randf"])) > 0.000001:
        return "Reloaded float generation should match serialized RNG state."

    if abs(manager.randf() - float(expected["utility_randf"])) > 0.000001:
        return "randf helper should produce identical values after state restoration."

    if manager.randi_range("loot", 1, 100) != expected["loot_range"]:
        return "randi_range helper should reproduce the serialized range result."

    return null

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()
