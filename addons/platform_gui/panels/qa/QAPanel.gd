extends VBoxContainer

## Panel that orchestrates regression and diagnostic runs directly from the Platform GUI.
##
## The QA panel exposes quick actions for the grouped manifest runner
## streams log output as each manifest group executes, and caches recent runs so
## support engineers can jump to stored summaries or open generated log files.
## Results are sourced from the RNGProcessor controller, mirroring the CLI
## scripts (`run_generator_tests.gd`, `run_platform_gui_tests.gd`, and
## `run_diagnostics_tests.gd`), to keep middleware wiring consistent with the
## rest of the editor tooling.

@export var controller_path: NodePath

const _INFO_COLOR := Color(0.3, 0.6, 0.9)
const _SUCCESS_COLOR := Color(0.32, 0.7, 0.36)
const _ERROR_COLOR := Color(0.86, 0.23, 0.23)

var _run_suite_button: Button= null
var _diagnostic_selector: OptionButton= null
var _run_diagnostic_button: Button= null
var _refresh_diagnostics_button: Button= null
var _log_view: RichTextLabel= null
var _clear_log_button: Button= null
var _open_log_button: Button= null
var _log_path_field: LineEdit= null
var _status_label: RichTextLabel= null
var _history_list: ItemList= null
var _guidance_label: RichTextLabel= null

func _stringify(value: Variant) -> String:
    if value is String:
        return value
    if value == null:
        return ""
    return str(value)

var _controller_override: Object = null
var _cached_controller: Object = null
var _connected_controller: Object = null
var _diagnostic_catalog: Array = []
var _log_lines: PackedStringArray = PackedStringArray()
var _active_run_id: String = ""
var _active_log_path: String = ""
var _history_lookup: Dictionary = {}


func _ensure_nodes_ready() -> void:
    if _run_suite_button == null:
        _run_suite_button = get_node("%RunSuiteButton") as Button
    if _diagnostic_selector == null:
        _diagnostic_selector = get_node("%DiagnosticSelector") as OptionButton
    if _run_diagnostic_button == null:
        _run_diagnostic_button = get_node("%RunDiagnosticButton") as Button
    if _refresh_diagnostics_button == null:
        _refresh_diagnostics_button = get_node("%RefreshDiagnosticsButton") as Button
    if _log_view == null:
        _log_view = get_node("%LogView") as RichTextLabel
    if _clear_log_button == null:
        _clear_log_button = get_node("%ClearLogButton") as Button
    if _open_log_button == null:
        _open_log_button = get_node("%OpenLogButton") as Button
    if _log_path_field == null:
        _log_path_field = get_node("%LogPathField") as LineEdit
    if _status_label == null:
        _status_label = get_node("%StatusLabel") as RichTextLabel
    if _history_list == null:
        _history_list = get_node("%HistoryList") as ItemList
    if _guidance_label == null:
        _guidance_label = get_node("%GuidanceLabel") as RichTextLabel
func _ready() -> void:
    _ensure_nodes_ready()
    _log_view.bbcode_enabled = true
    _status_label.bbcode_enabled = true
    _guidance_label.bbcode_enabled = true
    _guidance_label.meta_clicked.connect(_on_meta_clicked)

    _run_suite_button.pressed.connect(_on_run_suite_pressed)
    _run_diagnostic_button.pressed.connect(_on_run_diagnostic_pressed)
    _refresh_diagnostics_button.pressed.connect(_on_refresh_diagnostics_pressed)
    _clear_log_button.pressed.connect(_on_clear_log_pressed)
    _open_log_button.pressed.connect(_on_open_log_pressed)
    _history_list.item_selected.connect(_on_history_selected)

    _log_path_field.editable = false

    _guidance_label.bbcode_text = "Capture the generator core, platform GUI, and diagnostics group output, then [url=res://devdocs/platform_gui_handbook.md#deterministic-qa-workflow]archive DebugRNG timelines[/url] via the Logs panel when failures occur."

    _ensure_controller_connections()
    _populate_diagnostics()
    _refresh_history()
    _update_buttons()

func set_controller_override(controller: Object) -> void:
    _ensure_nodes_ready()
    _controller_override = controller
    _cached_controller = null
    _ensure_controller_connections()
    _populate_diagnostics()
    _refresh_history()
    _update_buttons()

func clear_controller_override() -> void:
    _ensure_nodes_ready()
    _controller_override = null
    _cached_controller = null
    _ensure_controller_connections()
    _populate_diagnostics()
    _refresh_history()
    _update_buttons()

func refresh() -> void:
    _ensure_nodes_ready()
    _cached_controller = null
    _ensure_controller_connections()
    _populate_diagnostics()
    _refresh_history()
    _update_buttons()

func _on_run_suite_pressed() -> void:
    _ensure_nodes_ready()
    var controller := _get_controller()
    if controller == null or not controller.has_method("run_full_test_suite"):
        _set_status(_format_error("RNGProcessor controller unavailable; suite launch skipped."))
        return
    var run_id_variant := controller.call("run_full_test_suite")
    _handle_run_start(_stringify(run_id_variant), {"label": "Full suite"})

func _on_run_diagnostic_pressed() -> void:
    _ensure_nodes_ready()
    var controller := _get_controller()
    if controller == null or not controller.has_method("run_targeted_diagnostic"):
        _set_status(_format_error("RNGProcessor controller unavailable; diagnostic launch skipped."))
        return
    var selected_id := _get_selected_diagnostic_id()
    if selected_id == "":
        _set_status(_format_error("Select a diagnostic before launching."))
        return
    var run_id_variant := controller.call("run_targeted_diagnostic", selected_id)
    _handle_run_start(_stringify(run_id_variant), {"label": "Diagnostic %s" % selected_id})

func _on_refresh_diagnostics_pressed() -> void:
    _ensure_nodes_ready()
    _populate_diagnostics(true)

func _on_clear_log_pressed() -> void:
    _ensure_nodes_ready()
    _log_lines.clear()
    _log_view.bbcode_text = ""
    _active_log_path = ""
    _log_path_field.text = ""

func _on_open_log_pressed() -> void:
    _ensure_nodes_ready()
    if _active_log_path == "":
        _set_status(_format_error("Select a run with a saved log before opening."))
        return
    var global_path := ProjectSettings.globalize_path(_active_log_path)
    var error := OS.shell_open(global_path)
    if error != OK:
        _set_status(_format_error("Unable to open log at %s." % _active_log_path))
    else:
        _set_status(_format_info("Opened log at %s." % _active_log_path))

func _on_history_selected(index: int) -> void:
    _ensure_nodes_ready()
    if index < 0 or index >= _history_list.item_count:
        return
    var run_id := _stringify(_history_list.get_item_metadata(index))
    if not _history_lookup.has(run_id):
        return
    var record: Dictionary = _history_lookup[run_id]
    _active_run_id = run_id
    _active_log_path = _stringify(record.get("log_path", ""))
    _log_path_field.text = _active_log_path
    _render_history_log_hint(record)
    _update_buttons()

func _on_controller_run_started(run_id: String, request: Dictionary) -> void:
    _ensure_nodes_ready()
    _handle_run_start(run_id, request)

func _on_controller_run_output(run_id: String, line: String) -> void:
    _ensure_nodes_ready()
    if _active_run_id != "" and run_id != _active_run_id:
        return
    _append_log_line(line)

func _on_controller_run_completed(run_id: String, payload: Dictionary) -> void:
    _ensure_nodes_ready()
    var result: Dictionary = payload.get("result", {}) if payload.has("result") else {}
    var log_path := _stringify(payload.get("log_path", ""))
    _active_log_path = log_path
    _log_path_field.text = log_path
    var exit_code := int(result.get("exit_code", payload.get("exit_code", 1)))
    var status_lines := PackedStringArray()
    if exit_code == 0:
        status_lines.append(_format_success("QA run completed successfully."))
    else:
        status_lines.append(_format_error("QA run reported failures. Review the log for details."))
    var group_breakdown := _format_group_breakdown_lines(_resolve_group_summaries(payload, result))
    if not group_breakdown.is_empty():
        status_lines.append_array(group_breakdown)
    _set_status(_join_strings(status_lines, "\n"))
    _active_run_id = ""
    _refresh_history()
    _update_buttons()

func _handle_run_start(run_id: String, request: Dictionary) -> void:
    _ensure_nodes_ready()
    if run_id == "":
        _set_status(_format_error("QA run could not be started."))
        return
    _active_run_id = run_id
    _active_log_path = ""
    _log_lines.clear()
    _log_view.bbcode_text = ""
    _log_path_field.text = ""
    var label := _stringify(request.get("label", "QA run"))
    _set_status(_format_info("Started %s." % label))
    _update_buttons()

func _append_log_line(line: String) -> void:
    _ensure_nodes_ready()
    _log_lines.append(line)
    _log_view.bbcode_text = _join_strings(_log_lines, "\n")
    call_deferred("_scroll_log_to_end")

func _scroll_log_to_end() -> void:
    _ensure_nodes_ready()
    _log_view.scroll_to_line(_log_lines.size())

func _populate_diagnostics(force: bool = false) -> void:
    _ensure_nodes_ready()
    if not force and not _diagnostic_catalog.is_empty():
        return
    _diagnostic_catalog.clear()
    _diagnostic_selector.clear()
    var controller := _get_controller()
    if controller == null or not controller.has_method("get_available_qa_diagnostics"):
        _diagnostic_selector.add_item("No diagnostics available")
        _diagnostic_selector.disabled = true
        return
    var catalog_variant := controller.call("get_available_qa_diagnostics")
    var catalog: Array = catalog_variant if catalog_variant is Array else []
    if catalog.is_empty():
        _diagnostic_selector.add_item("No diagnostics available")
        _diagnostic_selector.disabled = true
        return
    _diagnostic_selector.disabled = false
    _diagnostic_catalog = catalog.duplicate(true)
    _diagnostic_selector.add_item("Select diagnostic", -1)
    for entry_variant in _diagnostic_catalog:
        var entry: Dictionary = entry_variant if entry_variant is Dictionary else {}
        var display_name := _stringify(entry.get("name", entry.get("id", "Unnamed diagnostic")))
        var id_value := _stringify(entry.get("id", ""))
        _diagnostic_selector.add_item(display_name)
        _diagnostic_selector.set_item_metadata(_diagnostic_selector.item_count - 1, id_value)

func _refresh_history() -> void:
    _ensure_nodes_ready()
    _history_list.clear()
    _history_lookup.clear()
    var controller := _get_controller()
    if controller == null or not controller.has_method("get_recent_qa_runs"):
        return
    var history_variant := controller.call("get_recent_qa_runs")
    var history: Array = history_variant if history_variant is Array else []
    for record_variant in history:
        if not (record_variant is Dictionary):
            continue
        var record: Dictionary = record_variant
        var run_id := _stringify(record.get("run_id", ""))
        var label := _format_history_label(record)
        var index := _history_list.add_item(label)
        _history_list.set_item_metadata(index, run_id)
        _history_lookup[run_id] = record.duplicate(true)
        var tooltip := _format_history_tooltip(record)
        if tooltip != "":
            _history_list.set_item_tooltip(index, tooltip)
    _update_buttons()

func _format_history_label(record: Dictionary) -> String:
    _ensure_nodes_ready()
    var label := _stringify(record.get("label", record.get("mode", "QA run")))
    var exit_code := int(record.get("exit_code", 1))
    var completed_ms := int(record.get("completed_at", 0))
    var completed := ""
    if completed_ms > 0:
        var seconds := completed_ms / 1000
        completed = Time.get_datetime_string_from_unix_time(seconds)
    var status_icon := "✅" if exit_code == 0 else "✗"
    var suffix := _format_group_history_suffix(record)
    if completed != "":
        if suffix != "":
            return "%s %s (%s) %s" % [status_icon, label, completed, suffix]
        return "%s %s (%s)" % [status_icon, label, completed]
    if suffix != "":
        return "%s %s %s" % [status_icon, label, suffix]
    return "%s %s" % [status_icon, label]

func _render_history_log_hint(record: Dictionary) -> void:
    _ensure_nodes_ready()
    var exit_code := int(record.get("exit_code", 1))
    var label := _stringify(record.get("label", record.get("mode", "QA run")))
    var lines := PackedStringArray()
    if exit_code == 0:
        lines.append(_format_success("%s completed successfully." % label))
    else:
        lines.append(_format_error("%s reported failures; inspect the stored log for details." % label))
    var breakdown := _format_group_breakdown_lines(_extract_group_summaries(record.get("group_summaries", [])))
    if not breakdown.is_empty():
        lines.append_array(breakdown)
    _set_status(_join_strings(lines, "\n"))

func _get_selected_diagnostic_id() -> String:
    _ensure_nodes_ready()
    var selected := _diagnostic_selector.get_selected_id()
    if selected >= 0:
        var metadata := _diagnostic_selector.get_item_metadata(_diagnostic_selector.selected)
        return _stringify(metadata)
    return ""

func _update_buttons() -> void:
    _ensure_nodes_ready()
    var controller := _get_controller()
    var controller_ready := controller != null
    var run_active := _active_run_id != ""
    _run_suite_button.disabled = not controller_ready or run_active
    _run_diagnostic_button.disabled = not controller_ready or run_active or _diagnostic_selector.disabled
    _refresh_diagnostics_button.disabled = not controller_ready
    _clear_log_button.disabled = _log_lines.is_empty()
    _open_log_button.disabled = _active_log_path == ""

func _set_status(message: String) -> void:
    _ensure_nodes_ready()
    _status_label.bbcode_text = message

func _format_info(message: String) -> String:
    _ensure_nodes_ready()
    return "[color=%s]%s[/color]" % [_INFO_COLOR.to_html(), message]

func _format_success(message: String) -> String:
    _ensure_nodes_ready()
    return "[color=%s]%s[/color]" % [_SUCCESS_COLOR.to_html(), message]

func _format_error(message: String) -> String:
    _ensure_nodes_ready()
    return "[color=%s]%s[/color]" % [_ERROR_COLOR.to_html(), message]

func _extract_group_summaries(source: Variant) -> Array:
    _ensure_nodes_ready()
    var summaries: Array = []
    if source is Array:
        for entry in source:
            if entry is Dictionary:
                summaries.append(entry)
    elif source is Dictionary:
        for entry in source.values():
            if entry is Dictionary:
                summaries.append(entry)
    return summaries

func _resolve_group_summaries(payload: Dictionary, result: Dictionary) -> Array:
    _ensure_nodes_ready()
    var primary := _extract_group_summaries(result.get("group_summaries", []))
    if not primary.is_empty():
        return primary
    return _extract_group_summaries(payload.get("group_summaries", []))

func _resolve_group_label_for_display(entry: Dictionary) -> String:
    _ensure_nodes_ready()
    var label := _stringify(entry.get("group_label", ""))
    if label.strip_edges() != "":
        return label
    var group_id := _stringify(entry.get("group_id", "")).strip_edges()
    if group_id == "":
        return "Group"
    var parts := group_id.split("_")
    var words := PackedStringArray()
    for part_variant in parts:
        var part := _stringify(part_variant).strip_edges()
        if part == "":
            continue
        words.append(part.capitalize())
    if words.is_empty():
        return group_id.capitalize()
    return _join_strings(words, " ")

func _resolve_group_badge_code(entry: Dictionary) -> String:
    _ensure_nodes_ready()
    var group_id := _stringify(entry.get("group_id", "")).strip_edges()
    if group_id == "":
        var label := _resolve_group_label_for_display(entry)
        if label == "":
            return "GRP"
        return label.substr(0, min(label.length(), 3)).to_upper()
    var pieces := group_id.split("_")
    var code := ""
    for piece_variant in pieces:
        var piece := _stringify(piece_variant).strip_edges()
        if piece == "":
            continue
        code += piece.substr(0, 1).to_upper()
    if code == "":
        return group_id.to_upper()
    return code

func _resolve_group_icon(entry: Dictionary) -> String:
    _ensure_nodes_ready()
    return "✅" if int(entry.get("exit_code", 0)) == 0 else "✗"

func _format_plain_group_summary(entry: Dictionary) -> String:
    _ensure_nodes_ready()
    var icon := _resolve_group_icon(entry)
    var label := _resolve_group_label_for_display(entry)
    var passed := int(entry.get("aggregate_passed", entry.get("suite_passed", 0)))
    var failed := int(entry.get("aggregate_failed", entry.get("suite_failed", 0)))
    var total := int(entry.get("aggregate_total", passed + failed))
    return "%s %s: %d passed, %d failed (%d total)" % [icon, label, passed, failed, total]

func _format_group_breakdown_lines(group_summaries: Array) -> PackedStringArray:
    _ensure_nodes_ready()
    var lines := PackedStringArray()
    for entry_variant in group_summaries:
        if not (entry_variant is Dictionary):
            continue
        var entry: Dictionary = entry_variant
        var summary_text := _format_plain_group_summary(entry)
        if int(entry.get("exit_code", 0)) == 0:
            lines.append(_format_success(summary_text))
        else:
            lines.append(_format_error(summary_text))
    return lines

func _format_group_history_suffix(record: Dictionary) -> String:
    _ensure_nodes_ready()
    var group_summaries := _extract_group_summaries(record.get("group_summaries", []))
    if group_summaries.is_empty():
        return ""
    var badges := PackedStringArray()
    for entry_variant in group_summaries:
        if not (entry_variant is Dictionary):
            continue
        var entry: Dictionary = entry_variant
        var code := _resolve_group_badge_code(entry)
        badges.append("%s%s" % [code, _resolve_group_icon(entry)])
    if badges.is_empty():
        return ""
    return "[%s]" % _join_strings(badges, " | ")

func _format_history_tooltip(record: Dictionary) -> String:
    _ensure_nodes_ready()
    var group_summaries := _extract_group_summaries(record.get("group_summaries", []))
    if group_summaries.is_empty():
        return ""
    var lines := PackedStringArray()
    lines.append(_stringify(record.get("label", record.get("mode", "QA run"))))
    for entry_variant in group_summaries:
        if not (entry_variant is Dictionary):
            continue
        var entry: Dictionary = entry_variant
        lines.append(_format_plain_group_summary(entry))
    return _join_strings(lines, "\n")

func _ensure_controller_connections() -> void:
    _ensure_nodes_ready()
    var controller := _get_controller()
    if controller == _connected_controller:
        return
    if _connected_controller != null and _is_object_valid(_connected_controller):
        if _connected_controller.has_signal("qa_run_started") and _connected_controller.is_connected("qa_run_started", Callable(self, "_on_controller_run_started")):
            _connected_controller.disconnect("qa_run_started", Callable(self, "_on_controller_run_started"))
        if _connected_controller.has_signal("qa_run_output") and _connected_controller.is_connected("qa_run_output", Callable(self, "_on_controller_run_output")):
            _connected_controller.disconnect("qa_run_output", Callable(self, "_on_controller_run_output"))
        if _connected_controller.has_signal("qa_run_completed") and _connected_controller.is_connected("qa_run_completed", Callable(self, "_on_controller_run_completed")):
            _connected_controller.disconnect("qa_run_completed", Callable(self, "_on_controller_run_completed"))
    _connected_controller = null
    if controller == null:
        return
    if controller.has_signal("qa_run_started"):
        controller.connect("qa_run_started", Callable(self, "_on_controller_run_started"), CONNECT_REFERENCE_COUNTED)
    if controller.has_signal("qa_run_output"):
        controller.connect("qa_run_output", Callable(self, "_on_controller_run_output"), CONNECT_REFERENCE_COUNTED)
    if controller.has_signal("qa_run_completed"):
        controller.connect("qa_run_completed", Callable(self, "_on_controller_run_completed"), CONNECT_REFERENCE_COUNTED)
    _connected_controller = controller

func _get_controller() -> Object:
    _ensure_nodes_ready()
    if _controller_override != null:
        return _controller_override
    if _cached_controller != null and _is_object_valid(_cached_controller):
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

func _join_strings(values: Variant, separator: String) -> String:
    _ensure_nodes_ready()
    var combined := ""
    var is_first := true
    for value in values:
        var segment := _stringify(value)
        if is_first:
            combined = segment
            is_first = false
        else:
            combined += "%s%s" % [separator, segment]
    return combined

func _is_object_valid(candidate: Object) -> bool:
    _ensure_nodes_ready()
    if candidate == null:
        return false
    if candidate is Node:
        return is_instance_valid(candidate)
    return true

func _on_meta_clicked(meta: Variant) -> void:
    _ensure_nodes_ready()
    if meta is String:
        OS.shell_open(ProjectSettings.globalize_path(_stringify(meta)))
