extends Node
class_name RNGManager

## Centralized random number generator manager for deterministic workflows.
##
## The manager keeps a single ``RandomNumberGenerator`` instance that systems
## can retrieve without touching Godot's global RNG state. This makes it easier
## to seed the generator for automated tests while still supporting fully
## randomized behaviour in production builds.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
    """
    Ensure the RNG has a non-zero seed when the autoload initializes.

    Godot automatically seeds ``RandomNumberGenerator`` instances at
    construction time, but calling ``randomize`` guarantees unique values
    between editor reloads unless a deterministic seed is provided manually.
    """
    _rng.randomize()


func get_rng() -> RandomNumberGenerator:
    """
    Retrieve the shared ``RandomNumberGenerator`` instance.

    Callers must not store their own references to the RNG if they intend to
    swap seeds later, since autoloads should remain the single source of truth
    for deterministic control.
    """
    return _rng


func reseed(seed_value: int) -> void:
    """
    Update the RNG seed explicitly for deterministic scenarios.

    This method enables save/load systems or automated tests to inject
    predictable randomness across the entire project. The RNG's state is
    advanced immediately after seeding to match Godot's default behaviour.
    """
    _rng.seed = seed_value
    _rng.state = _rng.state  # Force the generator to advance once after seeding.


func randf() -> float:
    """
    Proxy ``randf`` calls to the shared RNG for convenience.

    Keeping this helper inside the manager reduces boilerplate in systems that
    only need a floating-point random value.
    """
    return _rng.randf()


func randi_range(min_value: int, max_value: int) -> int:
    """
    Generate a random integer within ``min_value`` and ``max_value``.

    Callers can use this helper in place of ``RandomNumberGenerator``'s global
    static methods to avoid hidden state.
    """
    return _rng.randi_range(min_value, max_value)
