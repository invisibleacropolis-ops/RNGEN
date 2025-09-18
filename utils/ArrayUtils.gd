## Utility helpers for working with Array collections.
##
## This module wraps common random-selection functionality so that gameplay
## systems can share consistent logic.  The helpers are written to be
## deterministic whenever a custom [RandomNumberGenerator] instance is
## provided, which is useful for tests and replay systems.  When no RNG is
## provided the helpers will instantiate one on demand.
## Script class intentionally left unnamed to avoid collisions with name_generator ArrayUtils.
extends RefCounted

## Picks a single value from ``values`` using uniform probability.
## Returns ``null`` when the input array is empty.
static func pick_uniform(values: Array, rng: RandomNumberGenerator = null) -> Variant:
    if values.is_empty():
        return null

    var local_rng := rng
    if local_rng == null:
        local_rng = RandomNumberGenerator.new()
        local_rng.randomize()

    var index := local_rng.randi_range(0, values.size() - 1)
    return values[index]

## Picks a single value from ``values`` using the supplied ``weights``.
## ``weights`` must be the same size as ``values`` and every entry must be a
## non-negative number.  When the weights do not contain any positive value
## the selection gracefully falls back to ``pick_uniform``.
static func pick_weighted(values: Array, weights: Array, rng: RandomNumberGenerator = null) -> Variant:
    if values.is_empty() or weights.is_empty() or values.size() != weights.size():
        return pick_uniform(values, rng)

    var total_weight := 0.0
    for weight in weights:
        var normalized := max(float(weight), 0.0)
        total_weight += normalized

    if total_weight <= 0.0:
        return pick_uniform(values, rng)

    var local_rng := rng
    if local_rng == null:
        local_rng = RandomNumberGenerator.new()
        local_rng.randomize()

    var threshold := local_rng.randf() * total_weight
    var cumulative := 0.0

    for index in range(values.size()):
        cumulative += max(float(weights[index]), 0.0)
        if threshold <= cumulative:
            return values[index]

    return values.back()
