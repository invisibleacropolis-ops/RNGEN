extends "res://name_generator/strategies/GeneratorStrategy.gd"
class_name WordlistStrategy

const WordListResource := preload("res://name_generator/resources/WordListResource.gd")
const ArrayUtils := preload("res://name_generator/utils/ArrayUtils.gd")

const ERROR_NO_PATHS := "wordlists_missing"
const ERROR_LOAD_FAILED := "wordlist_load_failed"
const ERROR_INVALID_RESOURCE := "wordlist_invalid_type"
const ERROR_EMPTY_RESOURCE := "wordlist_empty"
const ERROR_NO_SELECTION := "wordlists_no_selection"

func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(["wordlist_paths"]),
        "optional": {
            "delimiter": TYPE_STRING,
            "use_weights": TYPE_BOOL,
        },
    }

func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    var validation_error: GeneratorError = _validate_config(config)
    if validation_error:
        return validation_error

    var resources_result: Variant = _collect_resources(config["wordlist_paths"])
    if resources_result is GeneratorError:
        return resources_result

    var resources: Array = resources_result if resources_result is Array else []
    if resources.is_empty():
        return emit_configured_error(
            config,
            ERROR_NO_PATHS,
            "No word list resources were provided.",
        )

    var selections: Array[String] = []
    var use_weights: bool = bool(config.get("use_weights", false))
    var delimiter: String = String(config.get("delimiter", " "))

    for resource in resources:
        var picked: Variant = _pick_from_resource(resource, use_weights, rng, config)
        if picked is GeneratorError:
            return picked
        if picked == null:
            continue
        selections.append(String(picked))

    if selections.is_empty():
        return emit_configured_error(
            config,
            ERROR_NO_SELECTION,
            "No entries were available from the configured word lists.",
        )

    return delimiter.join(selections)

func _collect_resources(sources: Variant) -> Variant:
    var normalized: Array = []
    var entries: Array = []

    if sources is PackedStringArray:
        entries.assign(sources)
    elif sources is Array:
        entries = sources.duplicate()
    else:
        return _make_error(
            "invalid_wordlist_paths_type",
            "'wordlist_paths' must be an Array of resource paths or WordListResource instances.",
            {"received_type": typeof(sources)},
        )

    for entry in entries:
        if entry is WordListResource:
            normalized.append(entry)
            continue

        if typeof(entry) != TYPE_STRING:
            return _make_error(
                "invalid_wordlist_entry",
                "Entries in 'wordlist_paths' must be strings or WordListResource instances.",
                {
                    "entry": entry,
                    "entry_type": typeof(entry),
                },
            )

        var path: String = String(entry).strip_edges()
        if path.is_empty():
            continue

        if not ResourceLoader.exists(path):
            return _make_error(
                ERROR_LOAD_FAILED,
                "Word list resource could not be found at '%s'." % path,
                {"path": path},
            )

        var resource: Resource = ResourceLoader.load(path)
        if resource == null:
            return _make_error(
                ERROR_LOAD_FAILED,
                "Failed to load word list resource at '%s'." % path,
                {"path": path},
            )

        if not (resource is WordListResource):
            return _make_error(
                ERROR_INVALID_RESOURCE,
                "Resource at '%s' must be a WordListResource." % path,
                {
                    "path": path,
                    "received_type": resource.get_class(),
                },
            )

        normalized.append(resource)

    return normalized

func _pick_from_resource(
    resource: WordListResource,
    use_weights: bool,
    rng: RandomNumberGenerator,
    config: Dictionary
) -> Variant:
    if use_weights and resource.has_weight_data():
        var weighted_entries: Array = resource.get_weighted_entries()
        if weighted_entries.is_empty():
            return emit_configured_error(
                config,
                ERROR_EMPTY_RESOURCE,
                "Word list resource is empty.",
            )
        return ArrayUtils.pick_weighted(weighted_entries, rng)

    var entries: Array = resource.get_uniform_entries()
    if entries.is_empty():
        return emit_configured_error(
            config,
            ERROR_EMPTY_RESOURCE,
            "Word list resource is empty.",
        )

    return ArrayUtils.pick_uniform(entries, rng)

func describe() -> Dictionary:
    var notes := PackedStringArray([
        "wordlist_paths accepts resource paths or preloaded WordListResource instances.",
        "Set use_weights to true to respect weighted entries when available.",
        "Delimiter controls how selections are joined in the final output.",
    ])
    return {
        "expected_config": get_config_schema(),
        "notes": notes,
    }
