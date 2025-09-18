extends RefCounted

const PANEL_SCENE := preload("res://addons/platform_gui/panels/hybrid/HybridPipelinePanel.tscn")
const HYBRID_PANEL_SCRIPT := preload("res://addons/platform_gui/panels/hybrid/HybridPipelinePanel.gd")
const PANEL_STUB_SCENE := preload("res://tests/test_assets/StrategyPanelStub.tscn")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("adds_steps_and_updates_alias", func(): _test_adds_steps_and_updates_alias())
    _run_test("builds_config_with_order", func(): _test_builds_config_with_order())
    _run_test("visualises_seed_and_stream", func(): _test_visualises_seed_and_stream())
    _run_test("surfaces_child_error_payload", func(): _test_surfaces_child_error_payload())

    return {
        "suite": "Platform GUI Hybrid Pipeline Panel",
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

func _test_adds_steps_and_updates_alias() -> Variant:
    var context := _make_panel()
    var panel: VBoxContainer = context["panel"]
    panel._ready()
    panel.set_strategy_panel_override("wordlist", PANEL_STUB_SCENE)

    panel._on_add_step_pressed()

    var step_list: ItemList = panel.get_node("EditorSection/StepSidebar/StepList")
    if step_list.item_count != 1:
        return "Adding a step should append it to the list."

    var alias_edit: LineEdit = panel.get_node("EditorSection/StepDetails/AliasRow/AliasEdit")
    alias_edit.editable = true
    alias_edit.text = "material"
    panel._on_alias_changed("material")

    if step_list.get_item_text(0).find("$material") == -1:
        return "Step list entries should reflect the configured alias placeholder."

    panel.free()
    (context["metadata"] as MetadataStub).free()
    (context["controller"] as ControllerStub).free()
    return null

func _test_builds_config_with_order() -> Variant:
    var context := _make_panel()
    var panel: VBoxContainer = context["panel"]
    panel._ready()
    panel.set_strategy_panel_override("wordlist", PANEL_STUB_SCENE)
    panel.set_strategy_panel_override("template", PANEL_STUB_SCENE)

    var selector: OptionButton = panel.get_node("EditorSection/StepSidebar/StepControls/StrategySelector")

    panel._on_add_step_pressed()
    var alias_edit: LineEdit = panel.get_node("EditorSection/StepDetails/AliasRow/AliasEdit")
    alias_edit.editable = true
    alias_edit.text = "phase_one"
    panel._on_alias_changed("phase_one")

    selector.select(1)
    panel._on_strategy_option_changed(1)
    panel._on_add_step_pressed()
    panel._on_step_selected(1)
    alias_edit.text = "phase_two"
    panel._on_alias_changed("phase_two")

    var steps: Array = panel.get("_steps")
    if steps.size() != 2:
        return "Hybrid panel should track both configured steps."

    var first_step: HYBRID_PANEL_SCRIPT.StepConfig = steps[0]
    var second_step: HYBRID_PANEL_SCRIPT.StepConfig = steps[1]
    var first_panel: Control = first_step.panel
    var second_panel: Control = second_step.panel
    first_panel.config_payload = {"strategy": "wordlist", "wordlist_paths": ["res://demo.tres"]}
    second_panel.config_payload = {"strategy": "template", "template_string": "[$phase_one]"}

    var step_list: ItemList = panel.get_node("EditorSection/StepSidebar/StepList")
    step_list.move_item(1, 0)
    var drag_event := InputEventMouseButton.new()
    drag_event.pressed = false
    panel._on_step_list_gui_input(drag_event)

    panel.get_node("PipelineControls/SeedRow/SeedInput").text = "hybrid_seed"
    panel._on_seed_changed("hybrid_seed")
    panel.get_node("PipelineControls/TemplateSection/TemplateInput").text = "$phase_one $phase_two"
    panel._on_template_changed("$phase_one $phase_two")

    var payload: Dictionary = panel.build_config_payload()
    var steps_payload: Array = payload.get("steps", [])
    if steps_payload.size() != 2:
        return "Payload should include all configured steps."
    if steps_payload[0].get("config", {}).get("strategy", "") != "template":
        return "Reordering should persist when building the pipeline payload."
    if steps_payload[0].get("store_as", "") != "phase_two":
        return "Payload should preserve the alias for each step."
    if payload.get("seed", "") != "hybrid_seed":
        return "Top-level seed should be included when provided."
    if payload.get("template", "") != "$phase_one $phase_two":
        return "Top-level template should pass through."

    panel.free()
    (context["metadata"] as MetadataStub).free()
    (context["controller"] as ControllerStub).free()
    return null

func _test_visualises_seed_and_stream() -> Variant:
    var context := _make_panel()
    var controller := context["controller"] as ControllerStub
    controller.latest_metadata = {
        "seed": "hybrid_seed",
        "rng_stream": "hybrid::pipeline",
    }
    var panel: VBoxContainer = context["panel"]
    panel._ready()
    panel.set_strategy_panel_override("wordlist", PANEL_STUB_SCENE)

    panel.get_node("PipelineControls/SeedRow/SeedInput").text = "hybrid_seed"
    panel._on_seed_changed("hybrid_seed")
    panel._on_add_step_pressed()
    var alias_edit: LineEdit = panel.get_node("EditorSection/StepDetails/AliasRow/AliasEdit")
    alias_edit.editable = true
    alias_edit.text = "material"
    panel._on_alias_changed("material")
    panel._on_preview_button_pressed()

    var tree: Tree = panel.get_node("PipelineTree")
    var root := tree.get_root()
    if root == null:
        return "Pipeline tree should initialise a root item."
    var pipeline_item := root.get_first_child()
    if pipeline_item == null:
        return "Pipeline overview should list the pipeline row."
    if pipeline_item.get_text(1).find("hybrid_seed") == -1:
        return "Pipeline row should surface the resolved seed hint."
    var step_item := pipeline_item.get_first_child()
    if step_item == null:
        return "Pipeline overview should include child steps."
    if step_item.get_text(3).find("step_material") == -1:
        return "Step rows should surface the derived seed segment."
    if step_item.get_text(4).find("hybrid::pipeline::step_material") == -1:
        return "Step rows should derive stream hints from middleware metadata."

    panel.free()
    (context["metadata"] as MetadataStub).free()
    controller.free()
    return null

func _test_surfaces_child_error_payload() -> Variant:
    var context := _make_panel()
    var metadata := context["metadata"] as MetadataStub
    metadata.guidance_map = {
        "hybrid": {
            "hybrid_step_error": {
                "message": "Check the failing step configuration.",
                "remediation": "Open the failing step and resolve its nested error.",
                "handbook_anchor": "middleware-errors-hybrid-pipelines",
                "handbook_label": "Hybrid pipelines",
            },
        },
        "wordlist": {
            "missing_resource": {
                "message": "Ensure the word list path is valid.",
                "remediation": "Browse to a valid WordListResource before retrying.",
                "handbook_anchor": "middleware-errors-wordlists",
                "handbook_label": "Word list datasets",
            },
        },
    }
    metadata.error_hints = {
        "hybrid": {"hybrid_step_error": "Check the failing step configuration."},
        "wordlist": {"missing_resource": "Ensure the word list path is valid."},
    }
    var controller := context["controller"] as ControllerStub
    controller.response = {
        "code": "missing_resource",
        "message": "Hybrid step material failed to generate.",
        "details": {
            "alias": "material",
            "index": 0,
            "received_path": "res://missing.tres",
        },
    }
    var panel: VBoxContainer = context["panel"]
    panel._ready()
    panel.set_strategy_panel_override("wordlist", PANEL_STUB_SCENE)

    panel._on_add_step_pressed()
    var alias_edit: LineEdit = panel.get_node("EditorSection/StepDetails/AliasRow/AliasEdit")
    alias_edit.editable = true
    alias_edit.text = "material"
    panel._on_alias_changed("material")

    panel._on_preview_button_pressed()

    var error_label: Label = panel.get_node("FeedbackSection/ErrorLabel")
    if not error_label.visible:
        return "Error label should surface when middleware returns a failure payload."
    var hint_label: Label = panel.get_node("FeedbackSection/HintLabel")
    if hint_label.text.find("Ensure the word list path is valid.") == -1:
        return "Hybrid panel should translate middleware error codes into friendly hints."
    if hint_label.text.find("Handbook: Word list datasets") == -1:
        return "Hybrid panel should surface handbook references in the inline hint."
    if hint_label.tooltip_text.find("Platform GUI Handbook") == -1:
        return "Hybrid panel should expose handbook context via tooltip text."
    var detail_label: RichTextLabel = panel.get_node("FeedbackSection/DetailLabel")
    if detail_label.bbcode_text.find("received_path") == -1:
        return "Error details should enumerate the middleware payload keys."
    var step_list: ItemList = panel.get_node("EditorSection/StepSidebar/StepList")
    var tint := step_list.get_item_custom_bg_color(0)
    if tint != Color(1.0, 0.9, 0.9, 1.0):
        return "Failing steps should be highlighted with the error tint."

    panel.free()
    metadata.free()
    controller.free()
    return null

func _make_panel() -> Dictionary:
    var panel := PANEL_SCENE.instantiate() as VBoxContainer
    var metadata := MetadataStub.new()
    var controller := ControllerStub.new()
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

    var error_hints: Dictionary = {}
    var guidance_map: Dictionary = {}

    func get_required_keys(_strategy_id: String) -> PackedStringArray:
        return PackedStringArray(["steps"])

    func get_optional_key_types(_strategy_id: String) -> Dictionary:
        return {"template": TYPE_STRING, "seed": TYPE_STRING}

    func get_default_notes(_strategy_id: String) -> PackedStringArray:
        return PackedStringArray(["Each step inherits the pipeline seed before deriving step aliases."])

    func get_generator_error_hints(strategy_id: String) -> Dictionary:
        return error_hints.get(strategy_id, {}).duplicate(true)

    func get_generator_error_guidance(strategy_id: String, code: String) -> Dictionary:
        if not guidance_map.has(strategy_id):
            return {}
        var strategy_guidance: Dictionary = guidance_map[strategy_id]
        if not strategy_guidance.has(code):
            return {}
        var entry: Variant = strategy_guidance[code]
        if entry is Dictionary:
            return (entry as Dictionary).duplicate(true)
        return {}

    func get_generator_error_hint(strategy_id: String, code: String) -> String:
        var guidance := get_generator_error_guidance(strategy_id, code)
        if not guidance.is_empty():
            return String(guidance.get("message", ""))
        if not error_hints.has(strategy_id):
            return ""
        return String(error_hints[strategy_id].get(code, ""))

class ControllerStub:
    extends Node

    var response: Variant = "Preview sample"
    var last_config: Dictionary = {}
    var latest_metadata: Dictionary = {}

    func generate(config: Dictionary) -> Variant:
        last_config = config.duplicate(true)
        return response

    func get_latest_generation_metadata() -> Dictionary:
        return latest_metadata.duplicate(true)
