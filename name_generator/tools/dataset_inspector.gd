extends SceneTree

## Walks the data directory and prints basic statistics about available datasets.
func _init():
    _inspect_datasets()
    quit()

func _inspect_datasets() -> void:
    var data_path := "res://data"
    var dir := DirAccess.open(data_path)
    if dir == null:
        push_error("Missing resource: data directory not found at %s" % data_path)
        return

    dir.list_dir_begin()
    var entry := dir.get_next()
    var found_any := false
    while entry != "":
        if dir.current_is_dir() and not entry.begins_with("."):
            found_any = true
            _report_directory("%s/%s" % [data_path, entry])
        entry = dir.get_next()
    dir.list_dir_end()

    if not found_any:
        push_warning("No dataset folders discovered under %s" % data_path)

func _report_directory(path: String) -> void:
    var child_dir := DirAccess.open(path)
    if child_dir == null:
        push_warning("Unable to open %s" % path)
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
        push_warning("%s is empty" % path)
    else:
        print("%s" % path)
        for item in contents:
            print("  - %s" % item)
