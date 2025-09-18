extends VBoxContainer

## Minimal strategy form stub used by HybridPipelinePanel tests.
##
## The stub exposes deterministic build_config_payload responses without touching
## Engine singletons or resource discovery. Tests can swap the payload at runtime
## to mimic different strategy form outputs while keeping the UI footprint small.

@export var strategy_id: String = ""
var config_payload: Dictionary = {}

func build_config_payload() -> Dictionary:
    if config_payload.is_empty():
        return {"strategy": strategy_id}
    return config_payload.duplicate(true)

func set_controller_override(_controller: Object) -> void:
    pass

func set_metadata_service_override(_service: Object) -> void:
    pass

func refresh() -> void:
    pass
