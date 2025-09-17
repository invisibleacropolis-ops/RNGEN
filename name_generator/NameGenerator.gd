extends Node
class_name NameGenerator

## High-level façade that exposes name generation utilities to the project.
##
## The autoload intentionally stays lightweight for now. It focuses on providing
## deterministic access to existing utility helpers so other systems can begin
## experimenting with content pipelines before the full generator matrix is
## implemented.

func pick_from_list(options: Array) -> Variant:
    """
    Select an entry from ``options`` using the shared ``RNGManager`` instance.

    The helper reuses ``ArrayUtils`` so we benefit from its input validation and
    deterministic behaviour. When additional generation strategies come online we
    can expand this façade to route requests to dedicated modules.
    """
    ArrayUtils.assert_not_empty(options, "Name options")
    var rng := RNGManager.get_rng()
    return ArrayUtils.pick_random_deterministic(options, rng)


func pick_weighted(entries: Array) -> Variant:
    """
    Select a weighted entry from ``entries`` using the shared RNG.

    This ensures all consumers derive randomness from a single seed source. The
    API mirrors ``ArrayUtils.pick_weighted_random_deterministic`` but keeps the
    higher-level naming consistent for autoload consumers.
    """
    ArrayUtils.assert_not_empty(entries, "Weighted name entries")
    var rng := RNGManager.get_rng()
    return ArrayUtils.pick_weighted_random_deterministic(entries, rng)
