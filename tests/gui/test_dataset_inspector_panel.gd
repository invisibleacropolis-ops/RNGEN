extends RefCounted

const PANEL_SCENE := preload("res://addons/platform_gui/panels/datasets/DatasetInspectorPanel.tscn")
const STUB_SCRIPT_PATH := "res://tests/test_assets/dataset_inspector_stub.gd"

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()
    _run_test("renders_directory_listing", func(): _test_renders_directory_listing())
    _run_test("reports_warnings", func(): _test_reports_warnings())
    _run_test("opens_docs_via_external_override", func(): _test_opens_docs_via_external_override())
    _run_test("activates_syllable_builder", func(): _test_activates_syllable_builder())
    return {
        "suite": "Dataset Inspector Panel",
        "total": _total,
        "passed": _passed,
        "failed": _failed,
        "failures": _failures.duplicate(true),
    }

func _run_test(name: String, callable: Callable) -> void:
    _total += 1
    var message := callable.call()
    if message == null:
        _passed += 1
    else:
        _failed += 1
        _failures.append({"name": name, "message": String(message)})

func _test_renders_directory_listing() -> Variant:
    var context := _make_panel()
    var panel: Control = context["panel"]
    panel.set_dataset_inspector_script_path(STUB_SCRIPT_PATH)
    panel.run_inspection()
    var results: String = panel.get_results_bbcode()
    if results.find("res://tests/tmp_data/alpha") == -1:
        return "Directory heading should be rendered in the results block."
    if results.find("creatures.txt") == -1 or results.find("items.csv") == -1:
        return "Child entries should be listed beneath the directory heading."
    context["panel"].free()
    return null

func _test_reports_warnings() -> Variant:
    var context := _make_panel()
    var panel: Control = context["panel"]
    panel.set_dataset_inspector_script_path(STUB_SCRIPT_PATH)
    panel.run_inspection()
    var warnings: String = panel.get_warnings_bbcode()
    if warnings.find("⚠️") == -1:
        return "Warnings block should include an inline warning glyph."
    if warnings.find("beta is empty") == -1:
        return "Warning messages emitted by the inspector should surface in the panel."
    context["panel"].free()
    return null

func _test_opens_docs_via_external_override() -> Variant:
    var context := _make_panel()
    var panel: Control = context["panel"]
    var recorded: Array[String] = []
    panel.set_external_open_override(func(path: String): recorded.append(path))
    panel._on_docs_pressed()
    if recorded.size() != 1:
        return "Docs button should invoke external opener once."
    if recorded[0] != panel.dataset_docs_path:
        return "Docs button should forward the dataset guide path to the opener."
    context["panel"].free()
    return null

func _test_activates_syllable_builder() -> Variant:
    var context := _make_panel()
    var panel: Control = context["panel"]
    var editor := EditorInterfaceStub.new()
    panel.set_editor_interface_override(editor)
    panel._on_builder_pressed()
    if editor.activation_requests != ["Syllable Set Builder"]:
        return "Syllable builder quick-launch should request plugin activation."
    context["panel"].free()
    return null

func _make_panel() -> Dictionary:
    var panel := PANEL_SCENE.instantiate()
    panel._ready()
    return {"panel": panel}

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

class EditorInterfaceStub:
    extends RefCounted

    var activation_requests: Array[String] = []

    func set_plugin_enabled(name: String, enabled: bool) -> void:
        if enabled:
            activation_requests.append(name)
