extends Node
## Lightweight event bus used by Platform GUI controllers to fan out middleware events.

signal event_published(event_name: String, payload: Dictionary)

func publish(event_name: String, payload: Dictionary) -> void:
    ## Broadcast an event payload to subscribers.
    emit_signal("event_published", event_name, _duplicate_variant(payload))

func _duplicate_variant(value: Variant) -> Variant:
    if value is Dictionary:
        return (value as Dictionary).duplicate(true)
    if value is Array:
        return (value as Array).duplicate(true)
    return value
