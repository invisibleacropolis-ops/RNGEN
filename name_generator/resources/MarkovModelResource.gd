@tool
extends Resource
class_name MarkovModelResource

## Serializable Markov chain model consumed by MarkovChainStrategy.
## The resource keeps generation lightweight by precomputing the transition
## table ahead of time. Designers can author the data directly in the inspector
## or rely on tooling scripts in `name_generator/tools`.

@export_group("Model")
@export_range(1, 8, 1) var order: int = 2
@export var states: PackedStringArray = PackedStringArray()
@export var start_tokens: Array[Dictionary] = []
@export var transitions: Dictionary = {}
@export var end_tokens: PackedStringArray = PackedStringArray()
@export var default_temperature: float = 1.0
@export var token_temperatures: Dictionary = {}

@export_group("Metadata")
@export var locale: String = ""
@export var domain: String = ""
@export_multiline var notes: String = ""

func has_state(token: String) -> bool:
    return states.has(token)

func get_transition_block(token: String) -> Array:
    if not transitions.has(token):
        return []
    var block := transitions[token]
    if block is Array:
        return block
    return []
