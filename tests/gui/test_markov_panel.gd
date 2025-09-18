extends RefCounted

const PANEL_SCENE: PackedScene = preload("res://addons/platform_gui/panels/markov/MarkovPanel.tscn")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("loads_metadata_summary", func(): _test_loads_metadata_summary())
    _run_test("renders_resource_catalogue", func(): _test_renders_resource_catalogue())
    _run_test("summarises_markov_model", func(): _test_summarises_markov_model())
    _run_test("surfaces_validation_details", func(): _test_surfaces_validation_details())
    _run_test("handles_success_preview", func(): _test_handles_success_preview())

    return {
        "suite": "Platform GUI Markov Panel",
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
        return
    _failed += 1
    _failures.append({
        "name": name,
        "message": String(message),
    })

func _test_loads_metadata_summary() -> Variant:
    var metadata := MetadataStub.new()
    metadata.required_keys = PackedStringArray(["markov_model_path"])
    metadata.optional_key_types = {"max_length": TYPE_INT}
    metadata.notes = PackedStringArray(["Markov model note guidance."])

    var context := _make_panel(metadata)
    var panel: VBoxContainer = context["panel"]
    panel._ready()

    var summary_text: String = panel.get_node("MetadataSummary").text
    if summary_text.find("markov_model_path") == -1:
        return "Metadata summary should list required Markov keys."
    if summary_text.find("max_length") == -1:
        return "Metadata summary should describe optional max length expectations."

    var notes_text: String = panel.get_node("NotesLabel").text
    if notes_text.find("Markov model note guidance.") == -1:
        return "Metadata notes should surface Markov authoring guidance."

    panel.free()
    (context["metadata"] as MetadataStub).free()
    (context["controller"] as ControllerStub).free()
    return null

func _test_renders_resource_catalogue() -> Variant:
    var context := _make_panel(MetadataStub.new())
    var panel: VBoxContainer = context["panel"]
    panel._ready()

    var descriptors := [
        {
            "path": "res://data/markov/demo_one.tres",
            "display_name": "Demo One",
            "locale": "en",
            "domain": "people",
        },
        {
            "path": "res://data/markov/demo_two.tres",
            "display_name": "Demo Two",
            "locale": "",
            "domain": "",
        },
    ]
    panel.set_resource_catalog_override(descriptors)

    var resource_list: ItemList = panel.get_node("ResourceSection/ResourceList")
    if resource_list.item_count != 2:
        return "Resource browser should list each provided Markov model descriptor."

    var first_text := resource_list.get_item_text(0)
    if first_text.find("Demo One") == -1 or first_text.find("people") == -1:
        return "Resource entries should surface display name and metadata context."

    var first_metadata: Dictionary = resource_list.get_item_metadata(0)
    if first_metadata.get("path", "") != "res://data/markov/demo_one.tres":
        return "Resource metadata should preserve the original Markov resource path."

    panel.free()
    (context["metadata"] as MetadataStub).free()
    (context["controller"] as ControllerStub).free()
    return null

func _test_summarises_markov_model() -> Variant:
    var metadata := MetadataStub.new()
    var context := _make_panel(metadata)
    var panel: VBoxContainer = context["panel"]
    panel._ready()

    panel.set_resource_catalog_override([
        {
            "path": "res://tests/test_assets/markov_basic.tres",
            "display_name": "Basic",
        },
    ])

    var resource_list: ItemList = panel.get_node("ResourceSection/ResourceList")
    resource_list.select(0)
    panel._on_resource_selected(0)

    var summary_label: RichTextLabel = panel.get_node("ResourceSummary")
    if summary_label.bbcode_text.find("States") == -1 or summary_label.bbcode_text.find("Temperature overrides") == -1:
        return "Resource summary should list state counts and temperature override context."

    var health_label: RichTextLabel = panel.get_node("HealthLabel")
    if health_label.bbcode_text.find("start tokens") == -1:
        return "Health indicator should describe termination reachability."
    if health_label.bbcode_text.find("emit end tokens") == -1:
        return "Health indicator should highlight direct termination states."

    panel.free()
    metadata.free()
    (context["controller"] as ControllerStub).free()
    return null

func _test_surfaces_validation_details() -> Variant:
    var metadata := MetadataStub.new()
    var controller := ControllerStub.new()
    controller.response = {
        "code": "invalid_transition_weight_value",
        "message": "'weight' in transitions[ri] must be greater than zero.",
        "details": {
            "state": "ri",
            "received_value": 0,
        },
    }

    var panel := PANEL_SCENE.instantiate() as VBoxContainer
    panel.set_metadata_service_override(metadata)
    panel.set_controller_override(controller)
    panel._ready()
    panel.set_resource_catalog_override([
        {
            "path": "res://tests/test_assets/markov_basic.tres",
            "display_name": "Basic",
        },
    ])

    var resource_list: ItemList = panel.get_node("ResourceSection/ResourceList")
    resource_list.select(0)

    panel._on_preview_button_pressed()

    var validation_label: Label = panel.get_node("ValidationLabel")
    if not validation_label.visible:
        return "Validation label should appear when the middleware returns an error."
    if validation_label.text.find("must be greater than zero") == -1:
        return "Validation label should surface the middleware error message."

    var details_label: RichTextLabel = panel.get_node("ValidationDetails")
    if not details_label.visible:
        return "Validation details should surface when error payload contains diagnostic context."
    if details_label.bbcode_text.find("state") == -1 or details_label.bbcode_text.find("ri") == -1:
        return "Validation details should enumerate middleware error keys and values."

    panel.free()
    metadata.free()
    controller.free()
    return null

func _test_handles_success_preview() -> Variant:
    var metadata := MetadataStub.new()
    var controller := ControllerStub.new()
    controller.response = "Arcane sample"

    var panel := PANEL_SCENE.instantiate() as VBoxContainer
    panel.set_metadata_service_override(metadata)
    panel.set_controller_override(controller)
    panel._ready()
    panel.set_resource_catalog_override([
        {
            "path": "res://tests/test_assets/markov_basic.tres",
            "display_name": "Basic",
        },
    ])

    var resource_list: ItemList = panel.get_node("ResourceSection/ResourceList")
    resource_list.select(0)
    var max_length_spin: SpinBox = panel.get_node("OptionsSection/MaxLengthRow/MaxLengthSpin")
    max_length_spin.value = 6
    var seed_input: LineEdit = panel.get_node("PreviewRow/SeedInput")
    seed_input.text = "markov_seed"

    panel._on_preview_button_pressed()

    if controller.last_config.get("markov_model_path", "") != "res://tests/test_assets/markov_basic.tres":
        return "Preview should include the selected Markov model path."
    if controller.last_config.get("max_length", 0) != 6:
        return "Preview should pass through the max length spinner value when provided."
    if controller.last_config.get("seed", "") != "markov_seed":
        return "Preview should include the user-provided seed value."

    var preview_label: RichTextLabel = panel.get_node("PreviewOutput")
    if not preview_label.visible or preview_label.text.find("Arcane sample") == -1:
        return "Successful previews should surface the returned sample output."

    panel.free()
    metadata.free()
    controller.free()
    return null

func _make_panel(metadata: MetadataStub) -> Dictionary:
    var controller := ControllerStub.new()
    var panel := PANEL_SCENE.instantiate() as VBoxContainer
    panel.set_metadata_service_override(metadata)
    panel.set_controller_override(controller)
    return {
        "panel": panel,
        "metadata": metadata,
        "controller": controller,
    }

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

class MetadataStub:
    extends Node

    var required_keys: PackedStringArray = PackedStringArray()
    var optional_key_types: Dictionary = {}
    var notes: PackedStringArray = PackedStringArray()

    func get_required_keys(_strategy_id: String) -> PackedStringArray:
        return required_keys.duplicate()

    func get_optional_key_types(_strategy_id: String) -> Dictionary:
        return optional_key_types.duplicate(true)

    func get_default_notes(_strategy_id: String) -> PackedStringArray:
        return notes.duplicate()

class ControllerStub:
    extends Node

    var response: Variant = ""
    var last_config: Dictionary = {}

    func generate(config: Dictionary) -> Variant:
        last_config = config.duplicate(true)
        return response
