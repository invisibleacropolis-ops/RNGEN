## Abstract base class for name generation strategies.
##
## Strategies consume a configuration dictionary and emit generated values.
## They also expose a consistent error-reporting interface so the calling code
## can surface actionable feedback to designers or telemetry systems.
extends Resource
class_name GeneratorStrategy

## Emitted whenever the strategy cannot produce a result due to configuration or
## data issues.  ``code`` identifies the error while ``message`` contains a
## user-facing explanation.  ``details`` can include extra structured context.
signal generation_error(code: String, message: String, details: Dictionary)

## Strategies override this method to produce output.  The default
## implementation simply returns an empty string so subclasses are not forced to
## call ``super``.
func generate(config: Dictionary) -> String:
    return ""

## Helper for subclasses that need to emit configurable errors.  The
## configuration dictionary can provide a nested ``errors`` dictionary where
## keys correspond to the error ``code`` value.  When the key is absent the
## ``default_message`` parameter is used instead.
func emit_configured_error(config: Dictionary, code: String, default_message: String, details: Dictionary = {}) -> void:
    var message := default_message
    if config.has("errors"):
        var overrides := config.get("errors")
        if typeof(overrides) == TYPE_DICTIONARY:
            message = overrides.get(code, default_message)

    emit_signal("generation_error", code, message, details)
