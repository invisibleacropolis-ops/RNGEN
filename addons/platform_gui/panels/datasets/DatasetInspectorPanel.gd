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

const _STATUS_ICONS := {
    "info": "ℹ️",
    "warning": "⚠️",
    "error": "❌",
}

var _inspect_button: Button= null
var _builder_button: Button= null
var _docs_button: Button= null
var _status_label: RichTextLabel= null
var _results_display: RichTextLabel= null
var _warnings_block: VBoxContainer= null
var _warnings_display: RichTextLabel= null
var _context_label: RichTextLabel= null

var _editor_interface_override: Object = null
var _external_open_override: Callable = Callable()


func _ensure_nodes_ready() -> void:
    if _inspect_button == null:
        _inspect_button = get_node("%InspectButton") as Button
    if _builder_button == null:
        _builder_button = get_node("%SyllableBuilderButton") as Button
    if _docs_button == null:
        _docs_button = get_node("%DocsButton") as Button
    if _status_label == null:
        _status_label = get_node("%StatusLabel") as RichTextLabel
    if _results_display == null:
        _results_display = get_node("%ResultDisplay") as RichTextLabel
    if _warnings_block == null:
        _warnings_block = get_node("%WarningsBlock") as VBoxContainer
    if _warnings_display == null:
        _warnings_display = get_node("%WarningsDisplay") as RichTextLabel
    if _context_label == null:
        _context_label = get_node("%ContextLabel") as RichTextLabel
func _ready() -> void:
    _ensure_nodes_ready()
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
    _ensure_nodes_ready()
    ## Inject an editor-interface stub for automated tests.
    _editor_interface_override = interface

func clear_editor_interface_override() -> void:
    _ensure_nodes_ready()
    _editor_interface_override = null

func set_external_open_override(callable: Callable) -> void:
    _ensure_nodes_ready()
    ## Override external opening behaviour (e.g. during tests).
    _external_open_override = callable

func clear_external_open_override() -> void:
    _ensure_nodes_ready()
    _external_open_override = Callable()

func set_dataset_inspector_script_path(path: String) -> void:
    _ensure_nodes_ready()
    dataset_inspector_script_path = path.strip_edges()

func set_dataset_docs_path(path: String) -> void:
    _ensure_nodes_ready()
    dataset_docs_path = path.strip_edges()
    _refresh_context_message()

func run_inspection() -> void:
    _ensure_nodes_ready()
    ## Execute the dataset inspector script and render the captured output.
    var capture := _execute_inspector()
    _render_capture(capture)

func get_status_bbcode() -> String:
    _ensure_nodes_ready()
    return _status_label.bbcode_text

func get_results_bbcode() -> String:
    _ensure_nodes_ready()
    return _results_display.bbcode_text

func get_warnings_bbcode() -> String:
    _ensure_nodes_ready()
    return _warnings_display.bbcode_text

func _on_inspect_pressed() -> void:
    _ensure_nodes_ready()
    run_inspection()

func _on_builder_pressed() -> void:
    _ensure_nodes_ready()
    var editor := _get_editor_interface()
    if editor == null:
        _set_status("Enable the Syllable Set Builder plugin from Project > Project Settings > Plugins.", "warning")
        return
    if editor.has_method("set_plugin_enabled"):
        editor.call("set_plugin_enabled", "Syllable Set Builder", true)
    _set_status("Requested Syllable Set Builder activation. Check the right dock for \"Syllable Sets\".")

func _on_docs_pressed() -> void:
    _ensure_nodes_ready()
    _open_dataset_docs()

func _on_context_meta_clicked(meta: Variant) -> void:
    _ensure_nodes_ready()
    if String(meta) == "dataset_docs":
        _open_dataset_docs()

func _open_dataset_docs() -> void:
    _ensure_nodes_ready()
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
    _ensure_nodes_ready()
    _set_status("Run the dataset inspector to review folder health.")
    _results_display.bbcode_text = "[i]No inspection has been run yet.[/i]"
    _warnings_block.visible = false

func _render_capture(capture: Dictionary) -> void:
    _ensure_nodes_ready()
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
    _ensure_nodes_ready()
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
    _ensure_nodes_ready()
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
    _ensure_nodes_ready()
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
    var script_resource := load(script_path)
    if script_resource == null:
        capture["errors"].append("Unable to load dataset inspector script.")
        return capture
    if not (script_resource is Script):
        capture["errors"].append("Dataset inspector must be a valid Script resource.")
        return capture
    var inspector_script: Script = script_resource
    capture = _capture_messages(func():
        var instance: Object = inspector_script.new()
        if instance != null:
            instance.free()
    )
    return capture

func _capture_messages(callable: Callable) -> Dictionary:
    _ensure_nodes_ready()
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
    _ensure_nodes_ready()
    var channels: Array[StringName] = []
    channels.append(STDERR_CHANNEL)
    channels.append(STDOUT_CHANNEL)
    for warning_channel in WARNING_CHANNELS:
        channels.append(warning_channel as StringName)
    for error_channel in ERROR_CHANNELS:
        channels.append(error_channel as StringName)
    return channels

func _record_message(record: Dictionary, channel: StringName, message: String) -> void:
    _ensure_nodes_ready()
    var text := String(message).strip_edges()
    if channel == STDOUT_CHANNEL:
        (record["stdout"] as Array).append(text)
    elif channel == STDERR_CHANNEL or channel in ERROR_CHANNELS:
        (record["errors"] as Array).append(text)
    elif channel in WARNING_CHANNELS:
        (record["warnings"] as Array).append(text)

func _parse_directories(lines: Array) -> Array:
    _ensure_nodes_ready()
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
    _ensure_nodes_ready()
    var doc_path := dataset_docs_path if dataset_docs_path != "" else "res://devdocs/datasets.md"
    _context_label.bbcode_text = "Need guidance? Review the [url=dataset_docs]dataset production checklist[/url] before importing or regenerating assets."

func _set_status(message: String, severity: String = "info") -> void:
    _ensure_nodes_ready()
    var color := _INFO_COLOR
    var icon := _STATUS_ICONS.get(severity, _STATUS_ICONS["info"])
    if severity == "warning":
        color = _WARNING_COLOR
    elif severity == "error":
        color = _ERROR_COLOR
    _status_label.bbcode_text = "[color=%s]%s %s[/color]" % [color.to_html(), icon, message]

func _get_editor_interface() -> Object:
    _ensure_nodes_ready()
    if _editor_interface_override != null:
        return _editor_interface_override
    if Engine.has_singleton("EditorInterface"):
        return Engine.get_singleton("EditorInterface")
    return null

func _open_external(path: String) -> bool:
    _ensure_nodes_ready()
    if _external_open_override.is_valid():
        _external_open_override.call(path)
        return true
    if not OS.has_feature("editor"):
        return false
    var absolute_path := ProjectSettings.globalize_path(path)
    var error := OS.shell_open(absolute_path)
    return error == OK
