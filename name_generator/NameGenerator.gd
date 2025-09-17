
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


const GENERATOR_STRATEGY := preload("res://name_generator/strategies/GeneratorStrategy.gd")

## Registry of known strategy script paths keyed by their public identifier.
static var _strategy_paths := {
    "template": "res://name_generator/strategies/TemplateStrategy.gd",
}

## Cache instantiated strategy singletons to avoid repeated allocations.
static var _strategy_cache: Dictionary = {}

static func register_strategy(identifier: String, script_path: String) -> void:
    """
    Register or override a generator strategy.

    Supplying a ``script_path`` registers the given path. Passing an empty path
    removes the registration, which can be useful for tests that need to mock
    strategies.
    """
    if script_path == null or script_path.is_empty():
        _strategy_paths.erase(identifier)
        _strategy_cache.erase(identifier)
        return

    _strategy_paths[identifier] = script_path
    _strategy_cache.erase(identifier)

static func generate(config: Variant, rng: RandomNumberGenerator) -> Variant:
    """
    Generate a name using the strategy described by ``config``.

    Returns either the generated ``String`` or an instance of
    ``GeneratorStrategy.GeneratorError`` describing why the generation failed.
    """
    if typeof(config) != TYPE_DICTIONARY:
        return _make_error(
            "invalid_config_type",
            "Generator configuration must be provided as a Dictionary.",
            {
                "received_type": typeof(config),
                "type_name": Variant.get_type_name(typeof(config)),
            },
        )

    var dict_config: Dictionary = config
    if rng == null:
        rng = RandomNumberGenerator.new()

    if not dict_config.has("strategy"):
        return _make_error(
            "missing_strategy_key",
            "Generator configuration is missing the 'strategy' key.",
        )

    var strategy_identifier = dict_config["strategy"]
    if typeof(strategy_identifier) != TYPE_STRING:
        return _make_error(
            "invalid_strategy_type",
            "Generator configuration 'strategy' must be a String identifier.",
            {
                "received_type": typeof(strategy_identifier),
                "type_name": Variant.get_type_name(typeof(strategy_identifier)),
            },
        )

    var strategy := _get_strategy_instance(strategy_identifier)
    if strategy == null:
        return _make_error(
            "unknown_strategy",
            "No generator strategy registered for identifier '%s'." % strategy_identifier,
            {"identifier": strategy_identifier},
        )

    return strategy.generate(dict_config, rng)

static func _get_strategy_instance(identifier: String) -> GeneratorStrategy:
    if _strategy_cache.has(identifier):
        return _strategy_cache[identifier]

    if not _strategy_paths.has(identifier):
        return null

    var script_path: String = _strategy_paths[identifier]
    var script := load(script_path)
    if script == null:
        return null

    var instance = script.new()
    if not (instance is GENERATOR_STRATEGY):
        push_warning(
            "Strategy at %s does not extend GeneratorStrategy and will be ignored." % script_path
        )
        return null

    _strategy_cache[identifier] = instance
    return instance

static func _make_error(code: String, message: String, details: Dictionary = {}) -> GENERATOR_STRATEGY.GeneratorError:
    return GENERATOR_STRATEGY.GeneratorError.new(code, message, details)

