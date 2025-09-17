## Strategy that assembles a name by sampling entries from authored word lists.
##
## The configuration dictionary supports the following keys:
## - ``wordlist_paths``: Array of resource paths to [WordListResource] assets.
## - ``use_weights``: Optional boolean flag that enables weighted selection when
##   a list provides weight data.
## - ``delimiter``: Optional string used to join the selected entries.  Defaults
##   to a single space.
## - ``errors``: Optional dictionary mapping error codes to custom messages.
extends GeneratorStrategy
class_name WordlistStrategy

const ERROR_NO_PATHS := "wordlists_missing"
const ERROR_LOAD_FAILED := "wordlist_load_failed"
const ERROR_INVALID_RESOURCE := "wordlist_invalid_type"
const ERROR_EMPTY_RESOURCE := "wordlist_empty"
const ERROR_NO_SELECTION := "wordlists_no_selection"

func generate(config: Dictionary) -> String:
    var wordlist_paths := _normalize_paths(config.get("wordlist_paths", []))
    if wordlist_paths.is_empty():
        emit_configured_error(config, ERROR_NO_PATHS, "No word list resources were provided.")
        return ""

    var delimiter: String = config.get("delimiter", " ")
    var use_weights: bool = config.get("use_weights", false)
    var selections: Array[String] = []

    for path in wordlist_paths:
        var data := _load_wordlist(path, config)
        if data.is_empty():
            continue

        var entries: Array = data.get("entries", [])
        var weights: Array = data.get("weights", [])
        var selection := _select_entry(entries, weights, use_weights)
        if selection == null:
            continue
        selections.append(str(selection))

    if selections.is_empty():
        emit_configured_error(config, ERROR_NO_SELECTION, "No entries were available from the configured word lists.")
        return ""

    return selections.join(delimiter)

func _normalize_paths(raw_paths: Variant) -> Array[String]:
    var normalized: Array[String] = []
    if raw_paths is PackedStringArray:
        raw_paths = raw_paths.to_array()
    if raw_paths is Array:
        for path in raw_paths:
            if typeof(path) == TYPE_STRING and not String(path).is_empty():
                normalized.append(path)
    return normalized

func _load_wordlist(path: String, config: Dictionary) -> Dictionary:
    var resource := ResourceLoader.load(path)
    if resource == null:
        emit_configured_error(config, ERROR_LOAD_FAILED, "Failed to load word list resource at '%s'." % path, {"path": path})
        return {}

    if not resource is WordListResource:
        emit_configured_error(config, ERROR_INVALID_RESOURCE, "Resource at '%s' is not a WordListResource." % path, {"path": path})
        return {}

    var entries := resource.get_entries()
    if entries.is_empty():
        emit_configured_error(config, ERROR_EMPTY_RESOURCE, "Word list '%s' does not contain any entries." % path, {"path": path})
        return {}

    return {
        "entries": entries,
        "weights": resource.get_weights(),
    }

func _select_entry(entries: Array, weights: Array, use_weights: bool) -> Variant:
    if entries.is_empty():
        return null

    if use_weights and not weights.is_empty():
        return ArrayUtils.pick_weighted(entries, weights)

    return ArrayUtils.pick_uniform(entries)
