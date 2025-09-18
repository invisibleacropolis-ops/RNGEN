extends RichTextLabel
class_name CompatRichTextLabel

## Provides a Godot 3 style bbcode_text property for projects and tests that still
## rely on it. Godot 4 removed the writable property, but parse_bbcode is still
## available. The helper keeps an internal cache and forwards assignments to
## parse_bbcode so markup is rendered while callers can continue to inspect the
## legacy property.

var bbcode_text: String:
    set(value):
        _bbcode_text = String(value)
        _refresh_bbcode()
    get:
        return _bbcode_text

var _bbcode_text: String = ""

func _enter_tree() -> void:
    if _bbcode_text == "":
        _bbcode_text = text

func _ready() -> void:
    _refresh_bbcode()

func _refresh_bbcode() -> void:
    if not is_inside_tree():
        return
    bbcode_enabled = true
    parse_bbcode(_bbcode_text)
