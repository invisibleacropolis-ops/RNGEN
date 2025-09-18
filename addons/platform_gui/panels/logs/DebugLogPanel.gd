extends VBoxContainer

## Panel that visualises DebugRNG telemetry captured by the RNGProcessor.
##
## The panel reads structured telemetry from the active DebugRNG helper,
## renders section-specific summaries (timeline, warnings, stream usage,
## strategy errors), and offers an inline download helper so engineers can
## archive the raw TXT report without leaving the editor.

@export var controller_path: NodePath

const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")

const SECTION_ALL := 0
const SECTION_TIMELINE := 1
const SECTION_WARNINGS := 2
const SECTION_STREAMS := 3
const SECTION_STRATEGY_ERRORS := 4

const _INFO_COLOR := Color(0.3, 0.6, 0.9)
const _ERROR_COLOR := Color(0.86, 0.23, 0.23)
const _WARNING_COLOR := Color(0.82, 0.49, 0.09)

@onready var _refresh_button: Button = %RefreshButton
@onready var _section_selector: OptionButton = %SectionSelector
@onready var _log_display: RichTextLabel = %LogDisplay
@onready var _download_path: LineEdit = %DownloadPath
@onready var _download_button: Button = %DownloadButton
@onready var _status_label: RichTextLabel = %StatusLabel

var _controller_override: Object = null
var _cached_controller: Object = null
var _report_cache: Dictionary = {}

func _ready() -> void:
    _log_display.bbcode_enabled = true
    _status_label.bbcode_enabled = true
    _refresh_button.pressed.connect(_on_refresh_pressed)
    _download_button.pressed.connect(_on_download_pressed)
    _section_selector.item_selected.connect(_on_section_selected)
    _populate_sections()
    _update_display()

func set_controller_override(controller: Object) -> void:
    _controller_override = controller
    _cached_controller = null
    _update_button_states()

func clear_controller_override() -> void:
    _controller_override = null
    _cached_controller = null
    _update_button_states()

func refresh() -> void:
    _load_report()

func _populate_sections() -> void:
    _section_selector.clear()
    _section_selector.add_item("All sections", SECTION_ALL)
    _section_selector.add_item("Generation timeline", SECTION_TIMELINE)
    _section_selector.add_item("Warnings", SECTION_WARNINGS)
    _section_selector.add_item("Stream usage", SECTION_STREAMS)
    _section_selector.add_item("Strategy errors", SECTION_STRATEGY_ERRORS)
    _section_selector.selected = SECTION_ALL

func _on_refresh_pressed() -> void:
    _load_report()

func _on_download_pressed() -> void:
    if _report_cache.is_empty():
        _set_status(_format_error("Attach DebugRNG before downloading."))
        return
    var source_path := String(_report_cache.get("log_path", ""))
    if source_path == "":
        _set_status(_format_error("DebugRNG did not report a log path."))
        return
    if not FileAccess.file_exists(source_path):
        _set_status(_format_error("DebugRNG log not found at %s." % source_path))
        return
    var target_path := _download_path.text.strip_edges()
    if target_path == "":
        _set_status(_format_error("Provide a download path (e.g. user://debug_rng_copy.txt)."))
        return
    var content := FileAccess.get_file_as_string(source_path)
    var file := FileAccess.open(target_path, FileAccess.WRITE)
    if file == null:
        _set_status(_format_error("Unable to open %s for writing." % target_path))
        return
    file.store_string(content)
    _set_status("Saved DebugRNG report to %s." % target_path)

func _on_section_selected(index: int) -> void:
    _section_selector.selected = index
    _update_display()

func _load_report() -> void:
    var controller := _get_controller()
    if controller == null or not controller.has_method("get_debug_rng"):
        _report_cache = {}
        _set_status(_format_error("RNGProcessor controller unavailable."))
        _update_display()
        return

    var debug_rng: Object = controller.call("get_debug_rng")
    if debug_rng == null:
        _report_cache = {}
        _set_status(_format_error("DebugRNG helper is not attached."))
        _update_display()
        return
    if not debug_rng is DebugRNG and not debug_rng.has_method("read_current_log"):
        _report_cache = {}
        _set_status(_format_error("Attached helper does not expose read_current_log()."))
        _update_display()
        return

    var payload: Variant = debug_rng.call("read_current_log")
    if payload is Dictionary:
        _report_cache = (payload as Dictionary).duplicate(true)
        _set_status("Loaded DebugRNG report with %d entries." % _report_cache.get("entries", []).size())
    else:
        _report_cache = {}
        _set_status(_format_error("DebugRNG returned unexpected telemetry payload."))
    _update_display()

func _update_display() -> void:
    var lines := PackedStringArray()
    if _report_cache.is_empty():
        lines.append("DebugRNG helper inactive.")
        _log_display.bbcode_text = "\n".join(lines)
        _update_button_states()
        return

    lines.append_array(_render_session_header())
    lines.append("")
    lines.append_array(_render_section_entries(_section_selector.selected))
    _log_display.bbcode_text = "\n".join(lines)
    _update_button_states()

func _render_session_header() -> PackedStringArray:
    var lines := PackedStringArray()
    var started := String(_report_cache.get("session_started_at", "--"))
    var ended := String(_report_cache.get("session_ended_at", "--"))
    var active := bool(_report_cache.get("session_open", false))
    lines.append("[b]Session started:[/b] %s" % started)
    lines.append("[b]Session ended:[/b] %s" % (active ? "(active)" : ended))

    var metadata_variant := _report_cache.get("metadata", {})
    if metadata_variant is Dictionary and not (metadata_variant as Dictionary).is_empty():
        var metadata: Dictionary = metadata_variant
        var keys := metadata.keys()
        keys.sort_custom(func(a, b): return String(a) < String(b))
        lines.append("[b]Metadata[/b]")
        for key in keys:
            lines.append("• %s: %s" % [String(key), _stringify_value(metadata[key])])

    var stats_variant := _report_cache.get("stats", {})
    if stats_variant is Dictionary and not (stats_variant as Dictionary).is_empty():
        var stats: Dictionary = stats_variant
        lines.append("[b]Aggregate statistics[/b]")
        var stat_keys := stats.keys()
        stat_keys.sort_custom(func(a, b): return String(a) < String(b))
        for key in stat_keys:
            lines.append("• %s: %s" % [String(key), _stringify_value(stats[key])])

    return lines

func _render_section_entries(section: int) -> PackedStringArray:
    var lines := PackedStringArray()
    var entries_variant := _report_cache.get("entries", [])
    if not (entries_variant is Array):
        lines.append("No telemetry entries available.")
        return lines

    var entries: Array = entries_variant
    var count := 0
    for entry_variant in entries:
        if typeof(entry_variant) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_variant
        if not _entry_matches_section(entry, section):
            continue
        lines.append(_format_entry(entry))
        count += 1

    if count == 0:
        match section:
            SECTION_WARNINGS:
                lines.append("No warnings recorded.")
            SECTION_STREAMS:
                lines.append("No stream usage recorded.")
            SECTION_STRATEGY_ERRORS:
                lines.append("No strategy errors recorded.")
            SECTION_TIMELINE:
                lines.append("No generation activity recorded.")
            _:
                lines.append("No telemetry entries available.")

    return lines

func _entry_matches_section(entry: Dictionary, section: int) -> bool:
    var type_name := String(entry.get("type", ""))
    match section:
        SECTION_WARNINGS:
            return type_name == "warning"
        SECTION_STREAMS:
            return type_name == "stream_usage"
        SECTION_STRATEGY_ERRORS:
            return type_name == "strategy_error"
        SECTION_TIMELINE:
            return type_name in ["generation_started", "generation_completed", "generation_failed", "strategy_error"]
        _:
            return true

func _format_entry(entry: Dictionary) -> String:
    var type_name := String(entry.get("type", ""))
    var timestamp := String(entry.get("timestamp", ""))
    match type_name:
        "warning":
            return "[color=%s]⚠️ %s %s[/color]" % [_WARNING_COLOR.to_html(), timestamp, _stringify_value(entry.get("message", ""))]
        "strategy_error":
            return "[color=%s]‼ %s strategy=%s code=%s message=%s[/color]" % [
                _ERROR_COLOR.to_html(),
                timestamp,
                String(entry.get("strategy_id", "")),
                String(entry.get("code", "")),
                _stringify_value(entry.get("message", "")),
            ]
        "stream_usage":
            return "%s stream=%s context=%s" % [
                timestamp,
                String(entry.get("stream", "")),
                _stringify_value(entry.get("context", {})),
            ]
        "generation_started":
            return "[b]%s[/b] START strategy=%s seed=%s stream=%s" % [
                timestamp,
                entry.get("metadata", {}).get("strategy_id", ""),
                entry.get("metadata", {}).get("seed", ""),
                entry.get("metadata", {}).get("rng_stream", ""),
            ]
        "generation_completed":
            return "%s COMPLETE strategy=%s result=%s" % [
                timestamp,
                entry.get("metadata", {}).get("strategy_id", ""),
                _stringify_value(entry.get("result", "")),
            ]
        "generation_failed":
            return "[color=%s]%s FAIL strategy=%s code=%s details=%s[/color]" % [
                _ERROR_COLOR.to_html(),
                timestamp,
                entry.get("metadata", {}).get("strategy_id", ""),
                entry.get("error", {}).get("code", ""),
                _stringify_value(entry.get("error", {})),
            ]
        _:
            return "%s %s" % [timestamp, _stringify_value(entry)]

func _update_button_states() -> void:
    var has_report := not _report_cache.is_empty()
    _download_button.disabled = not has_report

func _set_status(message: String) -> void:
    _status_label.text = message if message.begins_with("[color=") else "[color=%s]%s[/color]" % [_INFO_COLOR.to_html(), message]

func _format_error(message: String) -> String:
    return "[color=%s]%s[/color]" % [_ERROR_COLOR.to_html(), message]

func _stringify_value(value: Variant) -> String:
    if value is String:
        return value
    var json := JSON.new()
    return json.stringify(value)

func _get_controller() -> Object:
    if _controller_override != null:
        return _controller_override
    if _cached_controller != null and is_instance_valid(_cached_controller):
        return _cached_controller
    if controller_path != NodePath("") and has_node(controller_path):
        var node := get_node(controller_path)
        if node != null:
            _cached_controller = node
            return _cached_controller
    if Engine.has_singleton("RNGProcessorController"):
        var singleton := Engine.get_singleton("RNGProcessorController")
        if singleton != null:
            _cached_controller = singleton
            return _cached_controller
    return null
