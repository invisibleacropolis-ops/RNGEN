extends RefCounted

const DATASET_INSPECTOR_PATH := "res://name_generator/tools/dataset_inspector.gd"
const TEMP_ROOT := "res://tests/tmp_data"
const PATCHED_SCRIPT_PATH := "res://tests/tmp_dataset_inspector_runner.gd"

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

var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _checks.clear()

    _record("missing_root_directory", func(): return _test_missing_root_directory())
    _record("empty_child_directory", func(): return _test_empty_child_directory())
    _record("populated_directory_listing", func(): return _test_populated_directory_listing())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    _cleanup_artifacts()

    return {
        "id": "dataset_inspector",
        "name": "Dataset inspector smoke-test diagnostic",
        "total": _checks.size(),
        "passed": _checks.size() - failures.size(),
        "failed": failures.size(),
        "failures": failures.duplicate(true),
    }

func _record(name: String, callable: Callable) -> void:
    var result := callable.call()
    var success := result == null
    _checks.append({
        "name": name,
        "success": success,
        "message": "" if success else String(result),
    })

func _test_missing_root_directory() -> Variant:
    _clear_temp_data()

    var capture := _execute_inspector()
    var errors: Array = capture.get("errors", [])
    if errors.size() != 1:
        return "Missing root should emit exactly one error message."

    var expected := "Data directory not found at %s" % TEMP_ROOT
    if String(errors[0]).find(expected) == -1:
        return "Error message should mention the missing dataset directory."

    if not capture.get("warnings", []).is_empty():
        return "Missing root should not emit warnings."

    if not capture.get("stdout", []).is_empty():
        return "Missing root should not print dataset listings."

    return null

func _test_empty_child_directory() -> Variant:
    _clear_temp_data()
    _ensure_directory(TEMP_ROOT)
    _ensure_directory("%s/empty_dataset" % TEMP_ROOT)

    var capture := _execute_inspector()
    if not capture.get("errors", []).is_empty():
        return "Empty child directories should not emit errors."

    var warnings: Array = capture.get("warnings", [])
    var expected := "%s/empty_dataset is empty" % TEMP_ROOT
    if not _messages_include(warnings, expected):
        return "Empty dataset folder should trigger an empty-directory warning."

    if not capture.get("stdout", []).is_empty():
        return "Empty dataset folders should not print listings."

    return null

func _test_populated_directory_listing() -> Variant:
    _clear_temp_data()
    _ensure_directory(TEMP_ROOT)

    var alpha := "%s/alpha" % TEMP_ROOT
    _ensure_directory(alpha)
    _write_text_file("%s/creatures.txt" % alpha, "dragon\n")
    _write_text_file("%s/items.csv" % alpha, "sword,shield\n")

    var beta := "%s/beta" % TEMP_ROOT
    _ensure_directory(beta)
    _write_text_file("%s/names.txt" % beta, "beta\n")
    _ensure_directory("%s/nested" % beta)

    var capture := _execute_inspector()

    if not capture.get("warnings", []).is_empty():
        return "Populated directories should not produce warnings."

    if not capture.get("errors", []).is_empty():
        return "Populated directories should not emit errors."

    var stdout: Array = capture.get("stdout", [])
    var expected_lines := [
        "%s/alpha" % TEMP_ROOT,
        "  - creatures.txt",
        "  - items.csv",
        "%s/beta" % TEMP_ROOT,
        "  - names.txt",
        "  - nested",
    ]

    for line in expected_lines:
        if not _messages_include(stdout, line):
            return "Expected inspector output '%s' was not captured." % line

    return null

func _execute_inspector() -> Dictionary:
    var script_path := _write_patched_script()
    var capture: Dictionary = {
        "stdout": [],
        "warnings": [],
        "errors": [],
        "other": [],
    }

    if script_path == "":
        capture["errors"].append("Failed to create patched dataset inspector script.")
        return capture

    var script := load(script_path)
    if script == null:
        capture["errors"].append("Unable to load patched dataset inspector script.")
    else:
        capture = _capture_messages(func():
            var instance := script.new()
            if instance != null:
                instance.free()
        )

    ResourceLoader.unload(script_path)
    _delete_file(script_path)

    return capture

func _capture_messages(callable: Callable) -> Dictionary:
    var record := {
        "stdout": [],
        "warnings": [],
        "errors": [],
        "other": [],
    }

    var registered: Array[StringName] = []
    var previous_error_setting := Engine.print_error_messages
    Engine.print_error_messages = false

    if EngineDebugger != null:
        for channel in _capture_channels():
            if EngineDebugger.has_capture(channel):
                continue
            var channel_name := channel
            var capture_callable := func(message: String, data: Array) -> bool:
                _record_message(record, channel_name, message)
                return true
            EngineDebugger.register_message_capture(channel_name, capture_callable)
            registered.append(channel_name)

    callable.call()

    if EngineDebugger != null:
        for channel in registered:
            EngineDebugger.unregister_message_capture(channel)

    Engine.print_error_messages = previous_error_setting

    return record

func _record_message(record: Dictionary, channel: StringName, message: String) -> void:
    var text := String(message).strip_edges()
    if channel == STDOUT_CHANNEL:
        record["stdout"].append(text)
    elif channel == STDERR_CHANNEL or channel in ERROR_CHANNELS:
        record["errors"].append(text)
    elif channel in WARNING_CHANNELS:
        record["warnings"].append(text)
    else:
        record["other"].append(text)

func _capture_channels() -> Array[StringName]:
    return [STDOUT_CHANNEL, STDERR_CHANNEL] + WARNING_CHANNELS + ERROR_CHANNELS

func _messages_include(messages: Array, target: String) -> bool:
    for entry in messages:
        if String(entry).find(target) != -1:
            return true
    return false

func _write_patched_script() -> String:
    var file := FileAccess.open(DATASET_INSPECTOR_PATH, FileAccess.READ)
    if file == null:
        return ""
    var source := file.get_as_text()
    file.close()

    source = source.replace('var data_path := "res://data"', 'var data_path := "%s"' % TEMP_ROOT)
    source = source.replace('    quit()', '    # quit() disabled during diagnostic execution')

    var output := FileAccess.open(PATCHED_SCRIPT_PATH, FileAccess.WRITE)
    if output == null:
        return ""
    output.store_string(source)
    output.close()

    return PATCHED_SCRIPT_PATH

func _ensure_directory(path: String) -> void:
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute)

func _write_text_file(path: String, contents: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return
    file.store_string(contents)
    file.close()

func _clear_temp_data() -> void:
    _remove_path_recursive(TEMP_ROOT)

func _delete_file(path: String) -> void:
    var absolute := ProjectSettings.globalize_path(path)
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(absolute)

func _remove_path_recursive(path: String) -> void:
    var absolute := ProjectSettings.globalize_path(path)
    if not DirAccess.dir_exists_absolute(absolute):
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(absolute)
        return

    var dir := DirAccess.open(path)
    if dir == null:
        return

    dir.list_dir_begin()
    var entry := dir.get_next()
    while entry != "":
        if entry.begins_with("."):
            entry = dir.get_next()
            continue
        var subpath := "%s/%s" % [path, entry]
        if dir.current_is_dir():
            _remove_path_recursive(subpath)
        else:
            DirAccess.remove_absolute(ProjectSettings.globalize_path(subpath))
        entry = dir.get_next()
    dir.list_dir_end()

    DirAccess.remove_absolute(absolute)

func _cleanup_artifacts() -> void:
    _clear_temp_data()
    ResourceLoader.unload(PATCHED_SCRIPT_PATH)
    _delete_file(PATCHED_SCRIPT_PATH)

