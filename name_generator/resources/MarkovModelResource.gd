@tool
extends Resource

class_name MarkovModelResource

## MarkovModelResource encapsulates a precomputed Markov chain for name generation.
## Designers can serialize a simple character-transition table to keep runtime logic
## focused on selection rather than training.

@export_group("Model configuration")
## The order of the Markov chain, e.g., 1 for unigram, 2 for bigram models.
@export_range(1, 5, 1)
var order: int = 2

## Starting sequences seeded before generating characters.
@export var start_sequences: PackedStringArray = PackedStringArray()

## Transition probability table keyed by state -> dictionary of next character weights.
@export var transitions: Dictionary = {}

@export_group("Metadata")
## Locale hint describing the culture or language inspiration for the model.
@export var locale: String = ""

## Domain or thematic usage (e.g., "Arcane", "Military", "Cyberpunk").
@export var domain: String = ""

## Optional notes about rarity or curation guidance for designers.
@export_multiline
var rarity_notes: String = ""
