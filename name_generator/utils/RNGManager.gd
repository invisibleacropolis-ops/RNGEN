extends RefCounted
class_name RNGManager

"""
Utility helpers for deriving deterministic random number generator streams.

The Godot ``RandomNumberGenerator`` allows callers to control deterministic
simulation by setting explicit seeds. When nested systems need their own
streams, however, simply sharing the same RNG can introduce unintended state
coupling. ``RNGManager`` offers helpers to deterministically derive additional
streams from a parent RNG without mutating the parent state.
"""

static func derive_child_rng(
    parent_rng: RandomNumberGenerator,
    key: String,
    depth: int = 0,
) -> RandomNumberGenerator:
    """
    Create a deterministic child RNG for ``key`` using ``parent_rng`` as the root.

    The resulting RNG uses a derived seed computed from the parent RNG's seed,
    the provided ``key``, and the recursion ``depth``. This ensures that the
    same inputs always generate an identical RNG stream while still keeping
    streams for different keys or depths isolated from each other.
    """
    if parent_rng == null:
        push_error("RNGManager.derive_child_rng requires a valid parent RNG instance.")
        assert(false)
        return RandomNumberGenerator.new()

    var parent_seed := parent_rng.seed
    var hash_input := "%s::%s::%s" % [parent_seed, key, depth]
    var derived_seed := hash(hash_input)

    var child := RandomNumberGenerator.new()
    child.seed = derived_seed
    return child
