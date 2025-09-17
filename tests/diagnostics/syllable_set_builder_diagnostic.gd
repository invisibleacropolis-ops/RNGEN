extends RefCounted

const SyllableSetBuilder := preload("res://name_generator/tools/SyllableSetBuilder.gd")

const WORD_LIST_FIXTURE_PATH := "res://tests/test_assets/wordlist_basic.tres"

var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _checks.clear()

    _record("parse_input_words_cleans_rows", func(): return _test_parse_input_words())
    _record("build_syllable_inventory_groups_tokens", func(): return _test_build_syllable_inventory())
    _record("normalize_output_path_handles_variants", func(): return _test_normalize_output_path())
    _record("word_list_selection_loads_entries", func(): return _test_word_list_selection())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    return {
        "id": "syllable_set_builder",
        "name": "SyllableSetBuilder diagnostic",
        "total": _checks.size(),
        "passed": _checks.size() - failures.size(),
        "failed": failures.size(),
        "failures": failures.duplicate(true),
    }

func _record(name: String, callable: Callable) -> void:
    var result = callable.call()
    var success := result == null
    _checks.append({
        "name": name,
        "success": success,
        "message": "" if success else String(result),
    })

func _test_parse_input_words() -> Variant:
    var builder := _create_builder_with_mocks()
    builder._text_edit.text = "# comment to ignore\nAlpha\nAlpha  \nBeta, trimmed\n  Gamma  \n"

    var words := builder._parse_input_words()
    var expected := PackedStringArray(["Alpha", "Beta", "Gamma"])

    if words != expected:
        return "Expected parsed words %s but received %s" % [expected, words]

    return null

func _test_build_syllable_inventory() -> Variant:
    var builder := _create_builder_with_mocks()

    var words := PackedStringArray(["Brave", "Mighty", "Shadow"])
    var inventory := builder._build_syllable_inventory(words)

    if not inventory.has("prefixes") or not (inventory["prefixes"] is PackedStringArray):
        return "Inventory should expose a PackedStringArray of prefixes"
    if not inventory.has("suffixes") or not (inventory["suffixes"] is PackedStringArray):
        return "Inventory should expose a PackedStringArray of suffixes"

    var prefixes: PackedStringArray = inventory["prefixes"]
    var suffixes: PackedStringArray = inventory["suffixes"]
    var middles: PackedStringArray = inventory.get("middles", PackedStringArray())

    if prefixes.size() != 3:
        return "Expected 3 prefixes from fixture words but received %d" % prefixes.size()
    if prefixes.find("Brav") == -1 or prefixes.find("Migh") == -1 or prefixes.find("Shad") == -1:
        return "Prefixes should include leading syllables for each fixture word"

    if suffixes.size() != 3:
        return "Expected 3 suffixes from fixture words but received %d" % suffixes.size()
    if suffixes.find("e") == -1 or suffixes.find("ty") == -1 or suffixes.find("ow") == -1:
        return "Suffixes should include trailing syllables for each fixture word"

    if not middles.is_empty():
        return "Two-syllable fixture words should not emit middle syllables"

    return null

func _test_normalize_output_path() -> Variant:
    var builder := _create_builder_with_mocks()

    var default_path := builder._normalize_output_path("fixture_output")
    if default_path != "res://data/syllable_sets/fixture_output.tres":
        return "Unexpected default output path: %s" % default_path

    var trimmed_path := builder._normalize_output_path("  spaced_name  ")
    if trimmed_path != "res://data/syllable_sets/spaced_name.tres":
        return "Unexpected trimmed output path: %s" % trimmed_path

    var explicit_resource := builder._normalize_output_path("res://custom/path.tres")
    if explicit_resource != "res://custom/path.tres":
        return "Explicit resource paths should be preserved"

    var auto_extension := builder._normalize_output_path("custom_file.tres")
    if auto_extension != "res://data/syllable_sets/custom_file.tres":
        return "File names with .tres should not gain duplicate extensions"

    return null

func _test_word_list_selection() -> Variant:
    var builder := _create_builder_with_mocks()

    if not ResourceLoader.exists(WORD_LIST_FIXTURE_PATH):
        return "Word list fixture missing at %s" % WORD_LIST_FIXTURE_PATH

    builder._on_word_list_selected(WORD_LIST_FIXTURE_PATH)

    var expected_text := "Brave\nMighty\nShadow"
    if builder._text_edit.text != expected_text:
        return "Loaded word list text should deduplicate entries and preserve sorted order"

    var words := builder._parse_input_words()
    var expected_words := PackedStringArray(["Brave", "Mighty", "Shadow"])
    if words != expected_words:
        return "Parsed words after loading WordListResource mismatch expected list"

    var inventory := builder._build_syllable_inventory(words)
    var prefixes: PackedStringArray = inventory.get("prefixes", PackedStringArray())
    if prefixes.size() != 3:
        return "Loaded WordListResource should produce three prefix syllables"

    if builder._status.text.find("Loaded 3 entries") == -1:
        return "Status message should report the number of loaded entries"

    return null

func _create_builder_with_mocks() -> SyllableSetBuilder:
    var builder := SyllableSetBuilder.new()

    if OS.has_feature("editor"):
        builder._text_edit = TextEdit.new()
        builder._output_name = LineEdit.new()
        builder._status = RichTextLabel.new()
    else:
        builder._text_edit = MockTextEdit.new()
        builder._output_name = MockLineEdit.new()
        builder._status = MockRichTextLabel.new()

    return builder

class MockTextEdit extends RefCounted:
    var text: String = ""

class MockLineEdit extends RefCounted:
    var text: String = ""

class MockRichTextLabel extends RefCounted:
    var text: String = ""
