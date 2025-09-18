extends RefCounted

const PANEL_SCENE := preload("res://addons/platform_gui/panels/wordlist/WordlistPanel.tscn")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("loads_metadata_summary", func(): _test_loads_metadata_summary())
    _run_test("renders_resource_catalogue", func(): _test_renders_resource_catalogue())
    _run_test("handles_preview_results", func(): _test_handles_preview_results())
    _run_test("surfaces_validation_errors", func(): _test_surfaces_validation_errors())

    return {
        "suite": "Platform GUI Wordlist Panel",
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
    metadata.required_keys = PackedStringArray(["wordlist_paths"])
    metadata.optional_key_types = {
        "delimiter": TYPE_STRING,
        "use_weights": TYPE_BOOL,
    }
    metadata.notes = PackedStringArray(["Wordlist note guidance."])

    var context := _make_panel(metadata)
    var panel: VBoxContainer = context["panel"]
    panel._ready()

    var summary_text := panel.get_node("MetadataSummary").text
    if summary_text.find("Requires: wordlist_paths") == -1:
        return "Metadata summary should list required keys from the cache."
    if summary_text.find("delimiter") == -1 or summary_text.find("weights") == -1:
        return "Metadata summary should describe optional key expectations."

    var notes_text := panel.get_node("NotesLabel").text
    if notes_text.find("Wordlist note guidance.") == -1:
        return "Metadata notes should surface narrative guidance for artists."

    panel.free()
    metadata.free()
    (context["controller"] as ControllerStub).free()
    return null

func _test_renders_resource_catalogue() -> Variant:
    var context := _make_panel(MetadataStub.new())
    var panel: VBoxContainer = context["panel"]
    panel._ready()

    var descriptors := [
        {
            "path": "res://data/example_alpha.tres",
            "display_name": "Alpha",
            "locale": "en",
            "domain": "people",
            "has_weights": true,
        },
        {
            "path": "res://data/example_beta.tres",
            "display_name": "Beta",
            "locale": "",
            "domain": "",
            "has_weights": false,
        },
    ]
    panel.set_resource_catalog_override(descriptors)

    var resource_list: ItemList = panel.get_node("ResourceSection/ResourceList")
    if resource_list.item_count != 2:
        return "Resource browser should list every provided WordListResource."

    var first_text := resource_list.get_item_text(0)
    if first_text.find("Alpha") == -1 or first_text.find("Weighted") == -1:
        return "Resource entries should surface weighting state inline."

    var first_metadata: Dictionary = resource_list.get_item_metadata(0)
    if first_metadata.get("path", "") != "res://data/example_alpha.tres":
        return "Resource metadata should preserve the original resource path."
    if first_metadata.get("locale", "") != "en" or first_metadata.get("domain", "") != "people":
        return "Resource metadata should include locale and domain context."

    panel.free()
    (context["metadata"] as MetadataStub).free()
    (context["controller"] as ControllerStub).free()
    return null

func _test_handles_preview_results() -> Variant:
    var metadata := MetadataStub.new()
    metadata.required_keys = PackedStringArray(["wordlist_paths"])

    var controller := ControllerStub.new()
    controller.response = "Arcane sigil"

    var panel := PANEL_SCENE.instantiate() as VBoxContainer
    panel.set_metadata_service_override(metadata)
    panel.set_controller_override(controller)
    panel._ready()

    panel.set_resource_catalog_override([
        {
            "path": "res://data/example_gamma.tres",
            "display_name": "Gamma",
            "locale": "en",
            "domain": "rituals",
            "has_weights": false,
        },
    ])

    var resource_list: ItemList = panel.get_node("ResourceSection/ResourceList")
    resource_list.select(0)
    var weight_toggle: CheckButton = panel.get_node("OptionsSection/UseWeights")
    weight_toggle.button_pressed = true
    var delimiter_input: LineEdit = panel.get_node("OptionsSection/DelimiterContainer/DelimiterInput")
    delimiter_input.text = "-"
    var seed_input: LineEdit = panel.get_node("PreviewRow/SeedInput")
    seed_input.text = "demo_seed"

    panel._on_preview_button_pressed()

    if controller.last_config.get("seed", "") != "demo_seed":
        return "Preview should include the user-specified seed value."
    if controller.last_config.get("use_weights", false) != true:
        return "Preview should respect the weight toggle state."
    if controller.last_config.get("delimiter", "") != "-":
        return "Preview should pass the delimiter through to the middleware."
    var paths: Array = controller.last_config.get("wordlist_paths", [])
    if paths.size() != 1 or paths[0] != "res://data/example_gamma.tres":
        return "Preview should only send the selected word list resources."

    var preview_label: RichTextLabel = panel.get_node("PreviewOutput")
    if not preview_label.visible or preview_label.text.find("Arcane sigil") == -1:
        return "Successful previews should surface the returned sample output."

    panel.free()
    metadata.free()
    controller.free()
    return null

func _test_surfaces_validation_errors() -> Variant:
    var metadata := MetadataStub.new()
    metadata.required_keys = PackedStringArray(["wordlist_paths"])

    var controller := ControllerStub.new()
    controller.response = {
        "code": "wordlists_missing",
        "message": "No word lists selected.",
    }

    var panel := PANEL_SCENE.instantiate() as VBoxContainer
    panel.set_metadata_service_override(metadata)
    panel.set_controller_override(controller)
    panel._ready()
    panel.set_resource_catalog_override([
        {
            "path": "res://data/example_delta.tres",
            "display_name": "Delta",
            "locale": "en",
            "domain": "alchemy",
            "has_weights": false,
        },
    ])

    var resource_list: ItemList = panel.get_node("ResourceSection/ResourceList")
    resource_list.select(0)

    panel._on_preview_button_pressed()

    var validation_label: Label = panel.get_node("ValidationLabel")
    if not validation_label.visible:
        return "Validation label should appear when the middleware returns an error."
    if validation_label.text.find("No word lists selected.") == -1:
        return "Validation feedback should surface the middleware error message."

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
