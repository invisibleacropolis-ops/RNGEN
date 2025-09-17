extends RefCounted
class_name RNGManager


## RNGManager derives deterministic child random streams from a root seed.
##
## The manager never mutates the supplied [RandomNumberGenerator]. Instead it
## records the seed and produces new, isolated [RandomNumberGenerator] instances
## for callers. Each child stream is obtained by hashing the root seed together
## with the hierarchical path supplied by the caller, ensuring that the same
## logical path always yields the same deterministic sequence.
const HASH_ALGORITHM := HashingContext.HASH_SHA256
const SEGMENT_SEPARATOR_BYTE := 0x1F

var _root_seed: int
var _path: PackedStringArray

func _init(seed_or_rng: Variant, path: PackedStringArray = PackedStringArray()):
    ## Create a new manager from either a seed value or an RNG instance.
    assert(seed_or_rng != null, "RNGManager requires a seed or RandomNumberGenerator instance.")

    if seed_or_rng is RandomNumberGenerator:
        var rng: RandomNumberGenerator = seed_or_rng
        _root_seed = int(rng.seed)
    else:
        _root_seed = int(seed_or_rng)

    _path = PackedStringArray(path)


func derive_rng(extra_segments: Array = []) -> RandomNumberGenerator:
    """
    Produce a deterministic [RandomNumberGenerator] for ``extra_segments``.

    ``extra_segments`` is appended to the manager's current path to form a new
    hierarchical address. The same path will always generate the same RNG
    sequence, making the operation safe for deterministic generation pipelines.
    """
    var path := PackedStringArray(_path)
    for segment in extra_segments:
        path.append(String(segment))

    return _make_rng_for_path(path)


func branch(extra_segments: Array = []) -> RNGManager:
    """
    Create a child ``RNGManager`` scoped to the provided ``extra_segments``.

    The child manager shares the root seed with its parent so any subsequent
    derivations remain deterministic relative to the original seed.
    """
    var path := PackedStringArray(_path)
    for segment in extra_segments:
        path.append(String(segment))

    return RNGManager.new(_root_seed, path)


func to_rng() -> RandomNumberGenerator:
    """Return an RNG representing the manager's current path."""
    if _path.is_empty():
        var rng := RandomNumberGenerator.new()
        rng.seed = _root_seed
        rng.state = _root_seed
        return rng

    return _make_rng_for_path(_path)


func get_path() -> PackedStringArray:
    """Expose the manager's path for debugging or logging purposes."""
    return PackedStringArray(_path)


func _make_rng_for_path(path: PackedStringArray) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    var seed := _compute_seed(path)
    rng.seed = seed
    rng.state = seed
    return rng


func _compute_seed(path: PackedStringArray) -> int:
    var context := HashingContext.new()
    context.start(HASH_ALGORITHM)

    context.update(str(_root_seed).to_utf8_buffer())
    for segment in path:
        context.update(PackedByteArray([SEGMENT_SEPARATOR_BYTE]))
        context.update(segment.to_utf8_buffer())

    var digest := context.finish()
    return _bytes_to_int(digest)


static func _bytes_to_int(bytes: PackedByteArray) -> int:
    var result: int = 0
    var count := min(bytes.size(), 8)
    for index in range(count):
        result |= int(bytes[index]) << (index * 8)
    return result

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

