extends SceneTree

## Walks the data directory and prints basic statistics about available datasets.
##
## The script doubles as a library for the Platform GUI: callers can invoke
## `collect_report()` to receive a structured snapshot without relying on
## runtime debugger hooks. Command-line usage (`godot --headless --script ...`)
## still streams the same stdout output and warnings so existing documentation
## remains accurate.
func _init(auto_run: bool = true):
    if auto_run:
        var report := collect_report()
        _emit_stdout(report)
        quit()

static func collect_report() -> Dictionary:
    ## Gather the dataset inspection report without printing to stdout.
    var report := {
        "directories": [],
        "warnings": [],
        "errors": [],
    }
    _inspect_datasets(report)
    return report

static func _inspect_datasets(report: Dictionary) -> void:
    var data_path := "res://data"
    var dir := DirAccess.open(data_path)
    if dir == null:
        _record_error(report, "Missing resource: data directory not found at %s" % data_path)
        return

    dir.list_dir_begin()
    var entry := dir.get_next()
    var found_any := false
    while entry != "":
        if dir.current_is_dir() and not entry.begins_with("."):
            found_any = true
            _report_directory(report, "%s/%s" % [data_path, entry])
        entry = dir.get_next()
    dir.list_dir_end()

    if not found_any:
        _record_warning(report, "No dataset folders discovered under %s" % data_path)

static func _report_directory(report: Dictionary, path: String) -> void:
    var child_dir := DirAccess.open(path)
    if child_dir == null:
        _record_warning(report, "Unable to open %s" % path)
        return

    child_dir.list_dir_begin()
    var contents := []
    var entry := child_dir.get_next()
    while entry != "":
        if not entry.begins_with("."):
            contents.append(entry)
        entry = child_dir.get_next()
    child_dir.list_dir_end()

    if contents.is_empty():
        _record_warning(report, "%s is empty" % path)
        return

    var directory_entry := {
        "path": path,
        "children": contents.duplicate(true),
    }
    (report["directories"] as Array).append(directory_entry)

static func _record_warning(report: Dictionary, message: String) -> void:
    push_warning(message)
    (report["warnings"] as Array).append(message)

static func _record_error(report: Dictionary, message: String) -> void:
    push_error(message)
    (report["errors"] as Array).append(message)

static func _emit_stdout(report: Dictionary) -> void:
    var directories: Array = report.get("directories", [])
    for entry_variant in directories:
        if not (entry_variant is Dictionary):
            continue
        var entry: Dictionary = entry_variant
        var path := String(entry.get("path", ""))
        if path.is_empty():
            continue
        print(path)
        var children: Array = entry.get("children", [])
        for child in children:
            print("  - %s" % String(child))
