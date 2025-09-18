extends RefCounted

## Lightweight persistence helper for Platform GUI user preferences.
##
## Preferences are stored in a ConfigFile under `user://` so editor
## customisations (e.g. last selected strategy or seed overrides) survive
## restarts. The helper intentionally exposes a minimal API to keep
## call-sites explicit and testable.

const _CONFIG_PATH := "user://platform_gui_prefs.cfg"

## Load a stored preference value.
##
## `section` groups related keys (e.g. panel identifiers) and `key`
## refers to the specific setting to retrieve. `default_value` is
## returned when the preference has not been written yet.
static func load_value(section: String, key: String, default_value: Variant = null) -> Variant:
    var config := ConfigFile.new()
    var error := config.load(_CONFIG_PATH)
    if error != OK:
        return default_value
    return config.get_value(section, key, default_value)

## Persist a preference value.
##
## The helper silently initialises the underlying ConfigFile when the
## preference file does not exist yet so panels can call it opportunistically.
static func save_value(section: String, key: String, value: Variant) -> void:
    var config := ConfigFile.new()
    var error := config.load(_CONFIG_PATH)
    if error != OK:
        config = ConfigFile.new()
    config.set_value(section, key, value)
    config.save(_CONFIG_PATH)
