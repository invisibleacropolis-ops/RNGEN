extends SceneTree

func _init():
    print("res://tests/tmp_data/alpha")
    print("  - creatures.txt")
    print("  - items.csv")
    push_warning("res://tests/tmp_data/beta is empty")
    quit()

static func collect_report() -> Dictionary:
    push_warning("res://tests/tmp_data/beta is empty")
    return {
        "directories": [{
            "path": "res://tests/tmp_data/alpha",
            "children": ["creatures.txt", "items.csv"],
        }],
        "warnings": ["res://tests/tmp_data/beta is empty"],
        "errors": [],
    }
