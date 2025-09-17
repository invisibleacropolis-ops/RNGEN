extends RefCounted

const RNGStreamRouter := preload("res://name_generator/utils/RNGManager.gd")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("integer_seed_paths", func(): _test_integer_seed_paths())
    _run_test("rng_instance_paths", func(): _test_rng_instance_paths())
    _run_test("derive_child_rng_consistency", func(): _test_derive_child_rng_consistency())

    return {
        "suite": "rng_stream_router",
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

func _test_integer_seed_paths() -> Variant:
    var router := RNGStreamRouter.new(13371337)

    var base_rng := router.to_rng()
    var repeat_base := router.to_rng()
    if base_rng.seed != repeat_base.seed:
        return "to_rng should be deterministic for identical path segments."

    var derived_alpha := router.derive_rng(["alpha"])
    var derived_alpha_repeat := router.derive_rng(["alpha"])
    if derived_alpha.seed != derived_alpha_repeat.seed:
        return "derive_rng must reproduce the same seed for identical paths."

    var derived_beta := router.derive_rng(["beta"])
    if derived_alpha.seed == derived_beta.seed:
        return "Distinct path segments should yield divergent seeds."

    var branch_alpha := router.branch(["alpha"])
    var branch_alpha_rng := branch_alpha.to_rng()
    if branch_alpha_rng.seed != derived_alpha.seed:
        return "Branching should preserve existing path segments when converted to an RNG."

    var branch_child := branch_alpha.derive_rng(["child"])
    var direct_child := router.derive_rng(["alpha", "child"])
    if branch_child.seed != direct_child.seed:
        return "Branching must retain the accumulated path when deriving new streams."

    return null

func _test_rng_instance_paths() -> Variant:
    var source_rng := RandomNumberGenerator.new()
    source_rng.seed = 987654321
    source_rng.state = source_rng.seed

    var router := RNGStreamRouter.new(source_rng)
    var derived := router.derive_rng(["gamma"])

    var seed_router := RNGStreamRouter.new(int(source_rng.seed))
    var derived_from_seed := seed_router.derive_rng(["gamma"])
    if derived.seed != derived_from_seed.seed:
        return "Routers constructed from RNG instances must honour the original seed."

    var branch := router.branch(["gamma", "delta"])
    var path := branch.get_path()
    if path.size() != 2 or path[0] != "gamma" or path[1] != "delta":
        return "Branch paths should retain all existing segments in order."

    var branch_rng := branch.derive_rng(["epsilon"])
    var direct_rng := router.derive_rng(["gamma", "delta", "epsilon"])
    if branch_rng.seed != direct_rng.seed:
        return "Nested branching should produce the same stream as direct derivation."

    return null

func _test_derive_child_rng_consistency() -> Variant:
    var parent := RandomNumberGenerator.new()
    parent.seed = 424242
    parent.state = parent.seed

    var expected := RNGStreamRouter.new(parent.seed).derive_rng(["child", 3])
    var actual := RNGStreamRouter.derive_child_rng(parent, "child", 3)
    if actual.seed != expected.seed:
        return "derive_child_rng should mirror manual derivation with identical segments."

    var default_depth := RNGStreamRouter.derive_child_rng(parent, "child")
    var explicit_zero := RNGStreamRouter.new(parent.seed).derive_rng(["child", 0])
    if default_depth.seed != explicit_zero.seed:
        return "derive_child_rng should default depth to zero when omitted."

    return null

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()
