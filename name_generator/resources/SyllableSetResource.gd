@tool
extends Resource

class_name SyllableSetResource

## A collection of syllable fragments used to assemble generated names.
## Designers can populate each list with syllables that suit the desired flavor.
@export_group("Syllable fragments")
## Optional prefixes that start generated names (e.g., "Ka", "Bar").
@export var prefixes: PackedStringArray = PackedStringArray()

## Optional middle syllables that appear between prefixes and suffixes.
## Leave empty to skip middle syllables entirely.
@export var middles: PackedStringArray = PackedStringArray()

## Optional suffixes that end generated names (e.g., "th", "ara").
@export var suffixes: PackedStringArray = PackedStringArray()

@export_group("Generation settings")
## Allow strategies to skip the middle syllable even when entries exist.
@export var allow_empty_middle: bool = true

## Hint describing the locale (language, culture) these syllables belong to.
@export var locale: String = ""

## Optional thematic domain for the syllables (e.g., "Fantasy", "Sci-Fi").
@export var domain: String = ""
