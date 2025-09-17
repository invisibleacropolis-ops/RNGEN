@tool
extends Resource
class_name MarkovModelResource

## MarkovModelResource describes a discrete-time Markov chain used to assemble
## generated names from weighted token transitions. Designers configure the
## resource inside the Godot editor and strategies consume it at runtime to
## produce deterministic-yet-flexible name sequences.

## Ordered collection of every token that can appear in the model. Tokens act as
## both the emitted syllable/character and the identifier for transition
## lookups. Including all tokens here enables simple validation and assists
## tooling when presenting possible transitions in editors.
@export var states: PackedStringArray = PackedStringArray()

## Weighted transitions for every token/state. Each key should map to an
## Array[Dictionary] where dictionaries use:
## - `token` ([String]): destination token/state identifier.
## - `weight` ([float]): positive weight used during sampling.
## - `temperature` ([float], optional): overrides the effective temperature when
##   sampling the transition.
@export var transitions: Dictionary = {}

## Collection of initial token candidates. Each entry follows the same structure
## as items in `transitions` — `token`, `weight`, and optional `temperature`.
## Entries may reference any token from `states` including those present in
## `end_tokens` when the model allows immediate termination.
@export var start_tokens: Array[Dictionary] = []

## Tokens that signal termination. When generation produces any token listed
## here the strategy stops without appending additional content. Designers
## typically include an explicit terminator token such as "<END>" or an empty
## string.
@export var end_tokens: PackedStringArray = PackedStringArray()

## Default temperature scalar applied during sampling. Values greater than 1.0
## flatten the distribution while values between 0 and 1 push the model toward
## higher-probability tokens. Setting the value to 1 leaves weights unchanged.
@export_range(0.01, 10.0, 0.01) var default_temperature: float = 1.0

## Optional per-token temperature overrides. When a key matches the token being
## sampled the specified value supersedes `default_temperature` for the duration
## of that selection.
@export var token_temperatures: Dictionary = {}
