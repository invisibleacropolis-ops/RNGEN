@tool
extends EditorPlugin

const SAVE_DIR := "res://data/syllable_sets"
const WORD_LIST_TYPE := preload("res://name_generator/resources/WordListResource.gd")
const SYLLABLE_SET_TYPE := preload("res://name_generator/resources/SyllableSetResource.gd")
const VOWEL_REGEX_PATTERN := "[aeiouyáéíóúäëïöüåæøœ]+"

var _dock: Control
var _text_edit: TextEdit
var _output_name: LineEdit
var _status: RichTextLabel
var _file_dialog: FileDialog
var _instructions: RichTextLabel

func _enter_tree() -> void:
    _dock = _build_dock()
    add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
    _file_dialog = FileDialog.new()
    _file_dialog.access = FileDialog.ACCESS_RESOURCES
    _file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _file_dialog.add_filter("*.tres ; Godot text resource")
    _file_dialog.add_filter("*.res ; Godot binary resource")
    _file_dialog.title = "Load Word List Resource"
    _file_dialog.connect("file_selected", Callable(self, "_on_word_list_selected"))
    _dock.add_child(_file_dialog)

func _exit_tree() -> void:
    if _dock:
        remove_control_from_docks(_dock)
        _dock.queue_free()
        _dock = null

func get_plugin_name() -> String:
    return "Syllable Set Builder"

func _build_dock() -> Control:
    var panel := PanelContainer.new()
    panel.name = "Syllable Sets"

    var scroll := ScrollContainer.new()
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_child(scroll)

    var root := VBoxContainer.new()
    root.custom_minimum_size = Vector2(320, 480)
    root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    root.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_theme_constant_override("separation", 8)
    scroll.add_child(root)

    var header := Label.new()
    header.text = "Syllable Set Builder"
    header.add_theme_font_size_override("font_size", 18)
    root.add_child(header)

    _instructions = RichTextLabel.new()
    _instructions.bbcode_enabled = true
    _instructions.fit_content = true
    _instructions.scroll_active = false
    _instructions.text = _build_instruction_text()
    root.add_child(_instructions)

    var load_button := Button.new()
    load_button.text = "Load WordListResource..."
    load_button.connect("pressed", Callable(self, "_on_load_word_list_pressed"))
    root.add_child(load_button)

    _text_edit = TextEdit.new()
    _text_edit.placeholder_text = "Paste one word per line or CSV rows with a 'word' column."
    _text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    root.add_child(_text_edit)

    var name_label := Label.new()
    name_label.text = "Output file name (saved to res://data/syllable_sets/):"
    root.add_child(name_label)

    _output_name = LineEdit.new()
    _output_name.placeholder_text = "example_locale_syllables.tres"
    root.add_child(_output_name)

    var save_button := Button.new()
    save_button.text = "Build syllable set"
    save_button.connect("pressed", Callable(self, "_on_build_pressed"))
    root.add_child(save_button)

    _status = RichTextLabel.new()
    _status.fit_content = true
    _status.scroll_active = false
    _status.bbcode_enabled = true
    root.add_child(_status)

    return panel

func _build_instruction_text() -> String:
    return "[b]Input formats[/b]\n" +
        "• Plain text: one entry per line. Blank lines and lines starting with '#' are ignored.\n" +
        "• CSV: the first comma-separated value is treated as the word. Additional columns are ignored.\n" +
        "• WordListResource: both simple and weighted entries are imported.\n\n" +
        "[b]Syllabification[/b]\n" +
        "Entries are split into syllables with a heuristic that keeps the first group as a prefix, optional middle groups as bridge syllables, " +
        "and the last group as a suffix. Single-syllable words are stored as both prefixes and suffixes so they can stand alone."

func _on_load_word_list_pressed() -> void:
    if _file_dialog:
        _file_dialog.popup_centered_ratio()

func _on_word_list_selected(path: String) -> void:
    var resource := load(path)
    if resource == null or not (resource is WORD_LIST_TYPE):
        _set_status("[color=yellow]The selected file is not a WordListResource.[/color]")
        return

    var words := PackedStringArray()
    if not resource.entries.is_empty():
        for entry in resource.entries:
            var clean := String(entry).strip_edges()
            if clean.is_empty():
                continue
            words.append(clean)
    if resource.has_weighted_entries():
        for entry_dict in resource.weighted_entries:
            if entry_dict.has("value"):
                var value := String(entry_dict["value"]).strip_edges()
                if value.is_empty():
                    continue
                words.append(value)

    words = _deduplicate(words)
    _text_edit.text = "\n".join(words)
    _set_status("Loaded %d entries from %s" % [words.size(), path])

func _on_build_pressed() -> void:
    var words := _parse_input_words()
    if words.is_empty():
        _set_status("[color=yellow]No valid words found. Provide entries before building.[/color]")
        return

    var save_path := _normalize_output_path(_output_name.text)
    if save_path.is_empty():
        _set_status("[color=yellow]Provide an output file name.[/color]")
        return

    _ensure_directory_exists(SAVE_DIR)

    var inventory := _build_syllable_inventory(words)
    if inventory.prefixes.is_empty() and inventory.suffixes.is_empty():
        _set_status("[color=yellow]Unable to derive syllables from the supplied entries.[/color]")
        return

    var resource := SYLLABLE_SET_TYPE.new()
    resource.prefixes = PackedStringArray(inventory.prefixes)
    resource.middles = PackedStringArray(inventory.middles)
    resource.suffixes = PackedStringArray(inventory.suffixes)

    var err := ResourceSaver.save(resource, save_path)
    if err != OK:
        _set_status("[color=red]Failed to save resource (%d).[/color]" % err)
        return

    _set_status("[color=green]Saved syllable set to %s[/color]" % save_path)

func _parse_input_words() -> PackedStringArray:
    var rows := PackedStringArray()
    if _text_edit == null:
        return rows

    var raw_lines := _text_edit.text.split("\n", false)
    for raw_line in raw_lines:
        var line := String(raw_line).strip_edges()
        if line.is_empty():
            continue
        if line.begins_with("#"):
            continue
        var value := line
        if line.contains(","):
            value = line.split(",")[0].strip_edges()
        if value.is_empty():
            continue
        rows.append(value)

    return _deduplicate(rows)

func _build_syllable_inventory(words: PackedStringArray) -> Dictionary:
    var prefix_map: Dictionary = {}
    var middle_map: Dictionary = {}
    var suffix_map: Dictionary = {}

    for word in words:
        var clean := String(word).strip_edges()
        if clean.is_empty():
            continue
        for token in clean.split(" "):
            var trimmed := String(token).strip_edges()
            if trimmed.is_empty():
                continue
            var syllables := _syllabify(trimmed)
            if syllables.is_empty():
                continue
            if syllables.size() == 1:
                var syllable := syllables[0]
                prefix_map[syllable] = true
                suffix_map[syllable] = true
            else:
                prefix_map[syllables[0]] = true
                suffix_map[syllables[syllables.size() - 1]] = true
                for i in range(1, syllables.size() - 1):
                    middle_map[syllables[i]] = true

    return {
        "prefixes": _sorted_keys(prefix_map),
        "middles": _sorted_keys(middle_map),
        "suffixes": _sorted_keys(suffix_map),
    }

func _syllabify(word: String) -> PackedStringArray:
    var normalized := String(word).strip_edges()
    if normalized.is_empty():
        return PackedStringArray()

    normalized = normalized.replace("'", "").replace("’", "")
    var segments := PackedStringArray()
    for piece in normalized.split("-", false):
        var trimmed := String(piece).strip_edges()
        if trimmed.is_empty():
            continue
        var sub_segments := _syllabify_token(trimmed)
        for segment in sub_segments:
            segments.append(segment)
    return segments

func _syllabify_token(token: String) -> PackedStringArray:
    var cleaned := String(token).strip_edges()
    if cleaned.is_empty():
        return PackedStringArray()

    var regex := RegEx.new()
    var err := regex.compile(VOWEL_REGEX_PATTERN)
    if err != OK:
        return PackedStringArray([cleaned])

    var lower := cleaned.to_lower()
    var matches := regex.search_all(lower)
    if matches.is_empty():
        return PackedStringArray([cleaned])

    var nuclei: Array[int] = []
    for match in matches:
        nuclei.append(match.get_start())

    var boundaries: Array[int] = []
    for i in range(nuclei.size() - 1):
        var cut := _estimate_boundary(lower, nuclei[i], nuclei[i + 1])
        boundaries.append(cut)

    var results: Array[String] = []
    var start := 0
    for boundary in boundaries:
        results.append(cleaned.substr(start, boundary - start))
        start = boundary
    results.append(cleaned.substr(start, cleaned.length() - start))
    return PackedStringArray(results)

func _estimate_boundary(lower: String, current_nucleus: int, next_nucleus: int) -> int:
    var consonant_run_length := max(0, next_nucleus - current_nucleus - 1)
    if consonant_run_length <= 0:
        return next_nucleus
    if consonant_run_length == 1:
        return next_nucleus
    return next_nucleus - 1

func _deduplicate(values: PackedStringArray) -> PackedStringArray:
    var map: Dictionary = {}
    for value in values:
        var key := String(value)
        map[key] = true
    var keys := map.keys()
    keys.sort()
    return PackedStringArray(keys)

func _sorted_keys(map: Dictionary) -> PackedStringArray:
    var keys := map.keys()
    keys.sort()
    return PackedStringArray(keys)

func _normalize_output_path(raw_input: String) -> String:
    var trimmed := String(raw_input).strip_edges()
    if trimmed.is_empty():
        return ""
    if not trimmed.ends_with(".tres"):
        trimmed += ".tres"
    if trimmed.begins_with("res://"):
        return trimmed
    return "%s/%s" % [SAVE_DIR, trimmed]

func _ensure_directory_exists(path: String) -> void:
    var absolute := ProjectSettings.globalize_path(path)
    var err := DirAccess.make_dir_recursive_absolute(absolute)
    if err != OK and err != ERR_ALREADY_EXISTS:
        push_error("Unable to create directory %s (error %d)" % [path, err])

func _set_status(message: String) -> void:
    if _status:
        _status.text = message

