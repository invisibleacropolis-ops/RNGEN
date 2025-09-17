## Deterministic helper that derives hierarchical RNG streams from a root seed.
##
## Strategies frequently need independent random streams while still honouring
## the master seed supplied by the runtime. This helper accepts either a seed or
## an existing [RandomNumberGenerator] and exposes helpers to derive additional
## RNG instances without mutating the parent state. Hashing the logical path
## into a 64-bit integer keeps the results reproducible across platforms.
class_name RNGStreamRouter
extends RefCounted

const HASH_ALGORITHM := HashingContext.HASH_SHA256
const SEGMENT_SEPARATOR_BYTE := 0x1F

var _root_seed: int
var _path: PackedStringArray

func _init(seed_or_rng: Variant, path: PackedStringArray = PackedStringArray()):
    assert(seed_or_rng != null, "RNGStreamRouter requires a seed or RNG instance.")

    if seed_or_rng is RandomNumberGenerator:
        var rng: RandomNumberGenerator = seed_or_rng
        _root_seed = int(rng.seed)
    else:
        _root_seed = int(seed_or_rng)

    _path = PackedStringArray(path)

func derive_rng(extra_segments: Array = []) -> RandomNumberGenerator:
    var segments := PackedStringArray(_path)
    for segment in extra_segments:
        segments.append(String(segment))
    return _make_rng_for_path(segments)

func branch(extra_segments: Array = []) -> RNGStreamRouter:
    var segments := PackedStringArray(_path)
    for segment in extra_segments:
        segments.append(String(segment))
    return RNGStreamRouter.new(_root_seed, segments)

func to_rng() -> RandomNumberGenerator:
    return _make_rng_for_path(_path)

func get_path() -> PackedStringArray:
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
    var value: int = 0
    var count := min(bytes.size(), 8)
    for index in range(count):
        value |= int(bytes[index]) << (index * 8)
    return value

static func derive_child_rng(
    parent_rng: RandomNumberGenerator,
    key: String,
    depth: int = 0
) -> RandomNumberGenerator:
    if parent_rng == null:
        push_error("RNGStreamRouter.derive_child_rng requires a valid parent RNG.")
        return RandomNumberGenerator.new()

    var router := RNGStreamRouter.new(parent_rng.seed)
    return router.derive_rng([key, depth])
