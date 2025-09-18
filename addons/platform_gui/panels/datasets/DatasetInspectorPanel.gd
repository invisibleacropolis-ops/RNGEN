extends VBoxContainer

## Platform GUI panel that runs the dataset inspector script from inside the editor.
##
## Artists can audit dataset folders without leaving Godot: the panel executes the
## existing `dataset_inspector.gd` tool via the editor API, captures stdout/warning
## messages, and renders folder health inline. Quick-launch helpers expose the
## Syllable Set Builder plugin plus direct links to the dataset authoring guide so
## narrative teams can jump straight into remediation work.

@export var dataset_inspector_script_path: String = "res://name_generator/tools/dataset_inspector.gd"
@export var dataset_docs_path: String = "res://devdocs/datasets.md"

const STDOUT_CHANNEL := StringName("stdout")
const STDERR_CHANNEL := StringName("stderr")
const WARNING_CHANNELS := [
    StringName("warning"),
    StringName("user_warning"),
    StringName("script_warning"),
]
const ERROR_CHANNELS := [
    StringName("error"),
    StringName("user_error"),
    StringName("script_error"),
]

const _INFO_COLOR := Color(0.27, 0.56, 0.86)
const _WARNING_COLOR := Color(0.82, 0.49, 0.09)
const _ERROR_COLOR := Color(0.86, 0.23, 0.23)

@onready var _inspect_button: Button = %InspectButton
@onready var _builder_button: Button = %SyllableBuilderButton
@onready var _docs_button: Button = %DocsButton
@onready var _status_label: RichTextLabel = %StatusLabel
@onready var _results_display: RichTextLabel = %ResultDisplay
@onready var _warnings_block: VBoxContainer = %WarningsBlock
@onready var _warnings_display: RichTextLabel = %WarningsDisplay
@onready var _context_label: RichTextLabel = %ContextLabel

var _editor_interface_override: Object = null
var _external_open_override: Callable = Callable()

func _ready() -> void:
    _status_label.bbcode_enabled = true
    _results_display.bbcode_enabled = true
    _warnings_display.bbcode_enabled = true
    _context_label.bbcode_enabled = true
    _inspect_button.pressed.connect(_on_inspect_pressed)
    _builder_button.pressed.connect(_on_builder_pressed)
    _docs_button.pressed.connect(_on_docs_pressed)
    _context_label.meta_clicked.connect(_on_context_meta_clicked)
    _refresh_context_message()
    _render_idle_state()

func set_editor_interface_override(interface: Object) -> void:
    ## Inject an editor-interface stub for automated tests.
    _editor_interface_override = interface

func clear_editor_interface_override() -> void:
    _editor_interface_override = null

func set_external_open_override(callable: Callable) -> void:
    ## Override external opening behaviour (e.g. during tests).
    _external_open_override = callable

func clear_external_open_override() -> void:
    _external_open_override = Callable()

func set_dataset_inspector_script_path(path: String) -> void:
    dataset_inspector_script_path = path.strip_edges()

func set_dataset_docs_path(path: String) -> void:
    dataset_docs_path = path.strip_edges()
    _refresh_context_message()

func run_inspection() -> void:
    ## Execute the dataset inspector script and render the captured output.
    var capture := _execute_inspector()
    _render_capture(capture)

func get_status_bbcode() -> String:
    return _status_label.bbcode_text

func get_results_bbcode() -> String:
    return _results_display.bbcode_text

func get_warnings_bbcode() -> String:
    return _warnings_display.bbcode_text

func _on_inspect_pressed() -> void:
    run_inspection()

func _on_builder_pressed() -> void:
    var editor := _get_editor_interface()
    if editor == null:
        _set_status("Enable the Syllable Set Builder plugin from Project > Project Settings > Plugins.", "warning")
        return
    if editor.has_method("set_plugin_enabled"):
        editor.call("set_plugin_enabled", "Syllable Set Builder", true)
    _set_status("Requested Syllable Set Builder activation. Check the right dock for \"Syllable Sets\".")

func _on_docs_pressed() -> void:
    _open_dataset_docs()

func _on_context_meta_clicked(meta: Variant) -> void:
    if String(meta) == "dataset_docs":
        _open_dataset_docs()

func _open_dataset_docs() -> void:
    var doc_path := dataset_docs_path
    if doc_path == "":
        _set_status("Dataset guide path not configured.", "warning")
        return
    var opened := _open_external(doc_path)
    if opened:
        _set_status("Opened dataset authoring guide.")
    else:
        _set_status("Unable to open dataset guide automatically; see %s." % doc_path, "warning")

func _render_idle_state() -> void:
    _set_status("Run the dataset inspector to review folder health.")
    _results_display.bbcode_text = "[i]No inspection has been run yet.[/i]"
    _warnings_block.visible = false

func _render_capture(capture: Dictionary) -> void:
    var stdout_lines: Array = capture.get("stdout", [])
    var directories := _parse_directories(stdout_lines)
    var warnings: Array = capture.get("warnings", [])
    var errors: Array = capture.get("errors", [])

    if not errors.is_empty():
        _set_status("Dataset inspection failed. Review the error output below.", "error")
    elif not warnings.is_empty():
        _set_status("Inspection completed with warnings.", "warning")
    elif directories.is_empty():
        _set_status("Dataset inspector did not report any folders.", "warning")
    else:
        _set_status("Dataset inspection completed without warnings.")

    _render_directory_listing(directories)
    _render_warning_block(warnings, errors)

func _render_directory_listing(directories: Array) -> void:
    if directories.is_empty():
        _results_display.bbcode_text = "[i]No dataset folders were reported.[/i]"
        return
    var lines := PackedStringArray()
    for entry in directories:
        if not (entry is Dictionary):
            continue
        var path := String(entry.get("path", ""))
        if path == "":
            continue
        lines.append("[b]%s[/b]" % path)
        var children: Array = entry.get("children", [])
        if children.is_empty():
            lines.append("  • [color=%s]No files detected[/color]" % _WARNING_COLOR.to_html())
        else:
            for child_variant in children:
                lines.append("  • %s" % String(child_variant))
        lines.append("")
    if lines.size() > 0 and lines[-1] == "":
        lines.remove_at(lines.size() - 1)
    _results_display.bbcode_text = "\n".join(lines)

func _render_warning_block(warnings: Array, errors: Array) -> void:
    var warning_lines := PackedStringArray()
    for message in warnings:
        warning_lines.append("⚠️ [color=%s]%s[/color]" % [_WARNING_COLOR.to_html(), String(message)])
    for message in errors:
        warning_lines.append("❌ [color=%s]%s[/color]" % [_ERROR_COLOR.to_html(), String(message)])
    if warning_lines.is_empty():
        _warnings_block.visible = false
        _warnings_display.bbcode_text = ""
    else:
        _warnings_block.visible = true
        _warnings_display.bbcode_text = "\n".join(warning_lines)

func _execute_inspector() -> Dictionary:
    var capture := {
        "stdout": [],
        "warnings": [],
        "errors": [],
    }
    var script_path := dataset_inspector_script_path
    if script_path == "":
        capture["errors"].append("Dataset inspector path is not configured.")
        return capture
    if not ResourceLoader.exists(script_path):
        capture["errors"].append("Dataset inspector not found at %s." % script_path)
        return capture
    var script := load(script_path)
    if script == null:
        capture["errors"].append("Unable to load dataset inspector script.")
        return capture
    capture = _capture_messages(func():
        var instance := script.new()
        if instance != null:
            instance.free()
    )
    return capture

func _capture_messages(callable: Callable) -> Dictionary:
    var record := {
        "stdout": [],
        "warnings": [],
        "errors": [],
    }
    var registered: Array[StringName] = []
    var previous_setting := Engine.print_error_messages
    Engine.print_error_messages = false
    if EngineDebugger != null:
        for channel in _capture_channels():
            if EngineDebugger.has_capture(channel):
                continue
            var capture_callable := func(message: String, _data: Array) -> bool:
                _record_message(record, channel, message)
                return true
            EngineDebugger.register_message_capture(channel, capture_callable)
            registered.append(channel)
    callable.call()
    if EngineDebugger != null:
        for channel in registered:
            EngineDebugger.unregister_message_capture(channel)
    Engine.print_error_messages = previous_setting
    return record

func _capture_channels() -> Array[StringName]:
    var channels := [STDERR_CHANNEL, STDOUT_CHANNEL]
    channels.append_array(WARNING_CHANNELS)
    channels.append_array(ERROR_CHANNELS)
    return channels

func _record_message(record: Dictionary, channel: StringName, message: String) -> void:
    var text := String(message).strip_edges()
    if channel == STDOUT_CHANNEL:
        (record["stdout"] as Array).append(text)
    elif channel == STDERR_CHANNEL or channel in ERROR_CHANNELS:
        (record["errors"] as Array).append(text)
    elif channel in WARNING_CHANNELS:
        (record["warnings"] as Array).append(text)

func _parse_directories(lines: Array) -> Array:
    var directories: Array = []
    var current := {}
    for variant in lines:
        var line := String(variant)
        if line.begins_with("  - "):
            if current.is_empty():
                continue
            var children: Array = current.get("children", [])
            children.append(line.substr(4, line.length() - 4))
            current["children"] = children
        elif line.strip_edges() != "":
            if not current.is_empty():
                directories.append(current.duplicate(true))
            current = {"path": line.strip_edges(), "children": []}
    if not current.is_empty():
        directories.append(current.duplicate(true))
    return directories

func _refresh_context_message() -> void:
    var doc_path := dataset_docs_path if dataset_docs_path != "" else "res://devdocs/datasets.md"
    _context_label.bbcode_text = "Need guidance? Review the [url=dataset_docs]dataset production checklist[/url] before importing or regenerating assets."

func _set_status(message: String, severity: String = "info") -> void:
    var color := _INFO_COLOR
    if severity == "warning":
        color = _WARNING_COLOR
    elif severity == "error":
        color = _ERROR_COLOR
    _status_label.bbcode_text = "[color=%s]%s[/color]" % [color.to_html(), message]

func _get_editor_interface() -> Object:
    if _editor_interface_override != null:
        return _editor_interface_override
    if Engine.has_singleton("EditorInterface"):
        return Engine.get_singleton("EditorInterface")
    return null

func _open_external(path: String) -> bool:
    if _external_open_override.is_valid():
        _external_open_override.call(path)
        return true
    if not OS.has_feature("editor"):
        return false
    var absolute_path := ProjectSettings.globalize_path(path)
    var error := OS.shell_open(absolute_path)
    return error == OK
