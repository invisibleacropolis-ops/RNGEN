extends RefCounted

const WORKSPACE_SCENE := preload("res://addons/platform_gui/workspaces/formulas/FormulasWorkspace.tscn")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()
    _run_test("loads_blueprint_and_panels", func(): _test_loads_blueprint_and_panels())
    _run_test("renders_seed_propagation", func(): _test_renders_seed_propagation())
    _run_test("injects_template_during_preview", func(): _test_injects_template_during_preview())
    return {
        "suite": "Formulas Workspace",
        "total": _total,
        "passed": _passed,
        "failed": _failed,
        "failures": _failures.duplicate(true),
    }

func _run_test(name: String, callable: Callable) -> void:
    _total += 1
    var message: Variant = callable.call()
    if message == null:
        _passed += 1
    else:
        _failed += 1
        _failures.append({"name": name, "message": String(message)})

func _test_loads_blueprint_and_panels() -> Variant:
    var context: Dictionary = _make_workspace()
    var workspace: Variant = context["workspace"]
    workspace._ready()
    workspace.set_controller_override(context["controller"])
    var hybrid_panel: Variant = workspace.get_node("Main/EditorSplit/HybridColumn/HybridPanelContainer/HybridPanel")
    var template_panel: Variant = workspace.get_node("Main/EditorSplit/TemplateColumn/TemplatePanelContainer/TemplatePanel")
    var hybrid_payload: Dictionary = hybrid_panel.build_config_payload()
    if hybrid_payload.get("steps", []).size() == 0:
        return "Hybrid panel should load blueprint steps during _ready."
    var template_payload: Dictionary = template_panel.build_config_payload()
    if template_payload.get("template_string", "") == "":
        return "Template panel should preload the blueprint template string."
    workspace.free()
    (context["controller"] as ControllerStub).free()
    return null

func _test_renders_seed_propagation() -> Variant:
    var context: Dictionary = _make_workspace()
    var workspace: Variant = context["workspace"]
    workspace._ready()
    workspace.set_controller_override(context["controller"])
    var tree: Tree = workspace.get_node("Main/PropagationPanel/PropagationVBox/PropagationTree")
    var root: TreeItem = tree.get_root()
    if root == null:
        return "Propagation tree should create a root item."
    var pipeline_item: TreeItem = root.get_first_child()
    if pipeline_item == null:
        return "Propagation tree should include pipeline seed row."
    var step_item: TreeItem = pipeline_item.get_first_child()
    if step_item == null:
        return "Propagation tree should list hybrid steps."
    if not step_item.get_text(1).begins_with("$"):
        return "Hybrid step rows should surface alias placeholders."
    workspace.free()
    (context["controller"] as ControllerStub).free()
    return null

func _test_injects_template_during_preview() -> Variant:
    var context: Dictionary = _make_workspace()
    var workspace: Variant = context["workspace"]
    workspace._ready()
    var controller: ControllerStub = context["controller"] as ControllerStub
    workspace.set_controller_override(controller)
    var template_panel: Variant = workspace.get_node("Main/EditorSplit/TemplateColumn/TemplatePanelContainer/TemplatePanel")
    var custom_template: Dictionary = {
        "strategy": "template",
        "template_string": "[custom_node]",
        "sub_generators": {
            "custom_node": {
                "strategy": "wordlist",
                "wordlist_paths": ["res://data/wordlists/skills/skill_verbs.tres"],
            },
        },
    }
    template_panel.apply_config_payload(custom_template)
    workspace._on_preview_pressed()
    var payload: Dictionary = controller.last_config
    if payload.get("strategy", "") != "hybrid":
        return "Preview should build a hybrid strategy payload."
    var steps: Array = payload.get("steps", [])
    if steps.is_empty():
        return "Preview payload should include hybrid steps."
    var template_found := false
    for entry_variant in steps:
        if typeof(entry_variant) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_variant
        if String(entry.get("store_as", "")) == "skill_sentence" or String(entry.get("store_as", "")) == "mission_body":
            var config: Variant = entry.get("config", {})
            if typeof(config) == TYPE_DICTIONARY and String(config.get("template_string", "")) == "[custom_node]":
                template_found = true
    if not template_found:
        return "Preview should inject the edited template configuration into the matching step."
    workspace.free()
    controller.free()
    return null

func _make_workspace() -> Dictionary:
    var workspace: Variant = WORKSPACE_SCENE.instantiate()
    var controller: ControllerStub = ControllerStub.new()
    return {"workspace": workspace, "controller": controller}

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

class ControllerStub:
    extends Node

    var last_config: Dictionary = {}
    var response: Variant = "Preview sample"

    func generate(config: Dictionary) -> Variant:
        last_config = config.duplicate(true)
        return response
