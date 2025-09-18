extends VBoxContainer

## Top-level workspace scene that guides artists through assembling
## hybrid-template formulas documented in `devdocs/sentences.md`.
##
## The workspace bundles curated blueprints, loads matching HybridStrategy
## and TemplateStrategy configurations, and visualises how seeds and aliases
## propagate through the combined pipeline. Inline help links directly to
## handbook anchors so narrative artists can cross-reference the underlying
## examples without leaving the editor.

@export var controller_path: NodePath
@export var metadata_service_path: NodePath
@export var handbook_path: String = "res://devdocs/platform_gui_handbook.md"

const SENTENCE_DOC_PATH := "res://devdocs/sentences.md"
const _ERROR_TINT := Color(1.0, 0.9, 0.9, 1.0)
const _INFO_TINT := Color(0.9, 0.97, 1.0, 1.0)

const BLUEPRINTS := [
    {
        "id": "skill_sentence",
        "display_name": "Skill sentence (hybrid + nested template)",
        "description": "Chains verb and theme word lists before resolving a nested template that stitches the payload together.",
        "handbook_anchor": "skill-description-sentence-template-inside-hybrid",
        "template_step_alias": "skill_sentence",
        "notes": [
            "Word lists live in res://data/wordlists/skills/ to mirror the devdocs example.",
            "Hybrid seed prefixes (skill_sentence_v1::step_$alias) keep previews deterministic when reusing payloads.",
        ],
        "hybrid": {
            "strategy": "hybrid",
            "seed": "skill_sentence_v1",
            "steps": [
                {
                    "store_as": "skill_verb",
                    "config": {
                        "strategy": "wordlist",
                        "wordlist_paths": ["res://data/wordlists/skills/skill_verbs.tres"],
                    },
                },
                {
                    "store_as": "skill_theme",
                    "config": {
                        "strategy": "wordlist",
                        "wordlist_paths": ["res://data/wordlists/skills/skill_themes.tres"],
                    },
                },
                {
                    "store_as": "skill_sentence",
                    "config": {
                        "strategy": "template",
                        "template_string": "[skill_sentence]",
                        "sub_generators": {
                            "skill_sentence": {
                                "strategy": "template",
                                "template_string": "The $skill_verb of $skill_theme [skill_payload]",
                                "sub_generators": {
                                    "skill_payload": {
                                        "strategy": "wordlist",
                                        "wordlist_paths": ["res://data/wordlists/skills/skill_payloads.tres"],
                                    },
                                },
                            },
                        },
                    },
                },
            ],
            "template": "$skill_sentence",
        },
        "template": {
            "strategy": "template",
            "template_string": "[skill_sentence]",
            "sub_generators": {
                "skill_sentence": {
                    "strategy": "template",
                    "template_string": "The $skill_verb of $skill_theme [skill_payload]",
                    "sub_generators": {
                        "skill_payload": {
                            "strategy": "wordlist",
                            "wordlist_paths": ["res://data/wordlists/skills/skill_payloads.tres"],
                        },
                    },
                },
            },
        },
    },
    {
        "id": "faction_mission",
        "display_name": "Faction mission brief",
        "description": "Builds a faction name, then layers a three-part mission hook with deterministic twists.",
        "handbook_anchor": "faction-mission-blurb-hybrid-with-nested-templates",
        "template_step_alias": "mission_body",
        "notes": [
            "All mission lists live under res://data/wordlists/factions/ so pipeline paths stay consistent with the handbook.",
            "Nested templates inherit the mission seed to guarantee matching verbs, targets, and twists during iteration.",
        ],
        "hybrid": {
            "strategy": "hybrid",
            "seed": "faction_mission_demo",
            "steps": [
                {
                    "store_as": "faction",
                    "config": {
                        "strategy": "wordlist",
                        "wordlist_paths": ["res://data/wordlists/factions/faction_titles.tres"],
                    },
                },
                {
                    "store_as": "mission_body",
                    "config": {
                        "strategy": "template",
                        "template_string": "[mission_body]",
                        "max_depth": 5,
                        "sub_generators": {
                            "mission_body": {
                                "strategy": "template",
                                "template_string": "$faction must [mission_action]",
                                "sub_generators": {
                                    "mission_action": {
                                        "strategy": "template",
                                        "template_string": "[mission_verb] [mission_target] [mission_twist]",
                                        "sub_generators": {
                                            "mission_verb": {
                                                "strategy": "wordlist",
                                                "wordlist_paths": ["res://data/wordlists/factions/mission_verbs.tres"],
                                            },
                                            "mission_target": {
                                                "strategy": "wordlist",
                                                "wordlist_paths": ["res://data/wordlists/factions/mission_targets.tres"],
                                            },
                                            "mission_twist": {
                                                "strategy": "wordlist",
                                                "wordlist_paths": ["res://data/wordlists/factions/mission_twists.tres"],
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            ],
            "template": "$mission_body",
        },
        "template": {
            "strategy": "template",
            "max_depth": 5,
            "template_string": "[mission_body]",
            "sub_generators": {
                "mission_body": {
                    "strategy": "template",
                    "template_string": "$faction must [mission_action]",
                    "sub_generators": {
                        "mission_action": {
                            "strategy": "template",
                            "template_string": "[mission_verb] [mission_target] [mission_twist]",
                            "sub_generators": {
                                "mission_verb": {
                                    "strategy": "wordlist",
                                    "wordlist_paths": ["res://data/wordlists/factions/mission_verbs.tres"],
                                },
                                "mission_target": {
                                    "strategy": "wordlist",
                                    "wordlist_paths": ["res://data/wordlists/factions/mission_targets.tres"],
                                },
                                "mission_twist": {
                                    "strategy": "wordlist",
                                    "wordlist_paths": ["res://data/wordlists/factions/mission_twists.tres"],
                                },
                            },
                        },
                    },
                },
            },
        },
    },
]

var _controller_override: Object = null
var _cached_controller: Object = null
var _metadata_service_override: Object = null
var _cached_metadata_service: Object = null
var _current_blueprint_id: String = ""
var _blueprint_lookup: Dictionary = {}

@onready var _blueprint_selector: OptionButton = %BlueprintSelector
@onready var _blueprint_notes: RichTextLabel = %BlueprintNotes
@onready var _handbook_link: RichTextLabel = %HandbookLink
@onready var _seed_tree: Tree = %PropagationTree
@onready var _hybrid_panel: Control = %HybridPanel
@onready var _template_panel: Control = %TemplatePanel
@onready var _preview_button: Button = %PreviewButton
@onready var _preview_label: RichTextLabel = %PreviewLabel

func _ready() -> void:
    _handbook_link.bbcode_enabled = true
    _handbook_link.meta_clicked.connect(_on_meta_clicked)
    _blueprint_notes.bbcode_enabled = true
    _blueprint_notes.meta_clicked.connect(_on_meta_clicked)
    _blueprint_selector.item_selected.connect(_on_blueprint_selected)
    _preview_button.pressed.connect(_on_preview_pressed)
    if _hybrid_panel.has_signal("configuration_changed"):
        _hybrid_panel.configuration_changed.connect(_on_hybrid_configuration_changed)
    if _template_panel.has_signal("configuration_changed"):
        _template_panel.configuration_changed.connect(_on_template_configuration_changed)
    _seed_tree.columns = 3
    _seed_tree.set_column_title(0, "Node")
    _seed_tree.set_column_title(1, "Details")
    _seed_tree.set_column_title(2, "Seed")
    _seed_tree.set_column_titles_visible(true)
    _populate_blueprint_selector()
    if _blueprint_selector.item_count > 0:
        _blueprint_selector.select(0)
        _apply_blueprint(String(_blueprint_selector.get_item_metadata(0)))

func set_controller_override(controller: Object) -> void:
    _controller_override = controller
    _cached_controller = null
    if _hybrid_panel.has_method("set_controller_override"):
        _hybrid_panel.call("set_controller_override", controller)
    if _template_panel.has_method("set_controller_override"):
        _template_panel.call("set_controller_override", controller)

func set_metadata_service_override(service: Object) -> void:
    _metadata_service_override = service
    _cached_metadata_service = null
    if _hybrid_panel.has_method("set_metadata_service_override"):
        _hybrid_panel.call("set_metadata_service_override", service)
    if _template_panel.has_method("set_metadata_service_override"):
        _template_panel.call("set_metadata_service_override", service)

func refresh() -> void:
    if _hybrid_panel.has_method("refresh"):
        _hybrid_panel.call("refresh")
    if _template_panel.has_method("refresh"):
        _template_panel.call("refresh")
    _rebuild_propagation_tree()

func _populate_blueprint_selector() -> void:
    _blueprint_lookup.clear()
    _blueprint_selector.clear()
    for blueprint in BLUEPRINTS:
        var id := String(blueprint.get("id", ""))
        if id == "":
            continue
        _blueprint_lookup[id] = blueprint
        var index := _blueprint_selector.item_count
        _blueprint_selector.add_item(String(blueprint.get("display_name", id)))
        _blueprint_selector.set_item_metadata(index, id)

func _on_blueprint_selected(index: int) -> void:
    var id := String(_blueprint_selector.get_item_metadata(index))
    _apply_blueprint(id)

func _apply_blueprint(id: String) -> void:
    if not _blueprint_lookup.has(id):
        return
    _current_blueprint_id = id
    var blueprint: Dictionary = _blueprint_lookup[id]
    _render_handbook_link(blueprint)
    _render_blueprint_notes(blueprint)
    if _hybrid_panel.has_method("apply_config_payload"):
        _hybrid_panel.call("apply_config_payload", blueprint.get("hybrid", {}))
    if _template_panel.has_method("apply_config_payload"):
        _template_panel.call("apply_config_payload", blueprint.get("template", {}))
    _sync_template_step()
    _rebuild_propagation_tree()
    _preview_label.visible = false

func _render_handbook_link(blueprint: Dictionary) -> void:
    var anchor := String(blueprint.get("handbook_anchor", ""))
    var link := _build_reference_url(SENTENCE_DOC_PATH, anchor)
    _handbook_link.bbcode_text = "[url=%s]Open handbook example[/url]" % link

func _render_blueprint_notes(blueprint: Dictionary) -> void:
    var description := String(blueprint.get("description", ""))
    var notes_variant := blueprint.get("notes", [])
    var bullet_lines: Array[String] = []
    if notes_variant is Array:
        for entry in notes_variant:
            bullet_lines.append(String(entry))
    var anchor := String(blueprint.get("handbook_anchor", ""))
    var link := _build_reference_url(SENTENCE_DOC_PATH, anchor)
    var text := "[b]%s[/b]\n[list]" % description
    for line in bullet_lines:
        text += "\n[*]" + line
    text += "\n[*]See [url=%s]devdocs/sentences.md[/url] for the full blueprint." % link
    text += "\n[/list]"
    _blueprint_notes.bbcode_text = text

func _sync_template_step() -> void:
    if not _blueprint_lookup.has(_current_blueprint_id):
        return
    var blueprint: Dictionary = _blueprint_lookup[_current_blueprint_id]
    var alias := String(blueprint.get("template_step_alias", ""))
    if alias == "":
        return
    if not _hybrid_panel.has_method("apply_step_config"):
        return
    var config := {} if not _template_panel.has_method("build_config_payload") else _template_panel.call("build_config_payload")
    if typeof(config) != TYPE_DICTIONARY:
        return
    _hybrid_panel.call("apply_step_config", alias, (config as Dictionary))

func _on_hybrid_configuration_changed() -> void:
    _rebuild_propagation_tree()

func _on_template_configuration_changed() -> void:
    _sync_template_step()

func _rebuild_propagation_tree() -> void:
    _seed_tree.clear()
    var root := _seed_tree.create_item()
    var pipeline_seed := "" if not _hybrid_panel.has_method("get_pipeline_seed") else String(_hybrid_panel.call("get_pipeline_seed"))
    var pipeline_item := _seed_tree.create_item(root)
    pipeline_item.set_text(0, "Pipeline seed")
    pipeline_item.set_text(1, pipeline_seed if pipeline_seed != "" else "Seed not set")
    pipeline_item.set_text(2, "hybrid")
    if pipeline_seed == "":
        _tint_row(pipeline_item, _ERROR_TINT)
        pipeline_item.set_tooltip_text(1, "Provide a top-level seed to keep previews deterministic.")
    var steps_info := []
    if _hybrid_panel.has_method("describe_seed_propagation"):
        steps_info = _hybrid_panel.call("describe_seed_propagation")
    if steps_info is Array:
        for entry in steps_info:
            if typeof(entry) != TYPE_DICTIONARY:
                continue
            var info: Dictionary = entry
            var alias := String(info.get("alias", ""))
            var strategy := String(info.get("strategy", ""))
            var seed_value := String(info.get("seed", ""))
            var step_item := _seed_tree.create_item(pipeline_item)
            step_item.set_text(0, "%s" % strategy.capitalize())
            step_item.set_text(1, "$%s" % alias)
            step_item.set_text(2, seed_value)
            if not bool(info.get("has_alias", true)):
                _tint_row(step_item, _ERROR_TINT)
                step_item.set_tooltip_text(1, "Assign a store_as alias so templates can reference this step.")
            elif pipeline_seed != "":
                _tint_row(step_item, _INFO_TINT)
            if strategy == "template":
                _render_template_structure(step_item, seed_value)

func _render_template_structure(parent: TreeItem, inherited_seed: String) -> void:
    if not _template_panel.has_method("evaluate_configuration"):
        return
    var evaluation := _template_panel.call("evaluate_configuration", inherited_seed)
    if typeof(evaluation) != TYPE_DICTIONARY:
        return
    var payload: Dictionary = evaluation
    var structure := payload.get("structure", {})
    if typeof(structure) != TYPE_DICTIONARY:
        return
    var template_item := _seed_tree.create_item(parent)
    template_item.set_text(0, "Template root")
    template_item.set_text(1, String(structure.get("template", "")))
    template_item.set_text(2, String(structure.get("seed", inherited_seed)))
    var errors := payload.get("errors", [])
    if errors is Array and not errors.is_empty():
        _tint_row(template_item, _ERROR_TINT)
        template_item.set_tooltip_text(1, "Template contains validation errors.")
    _render_template_children(template_item, structure.get("children", []))

func _render_template_children(parent: TreeItem, children: Array) -> void:
    for child_variant in children:
        if typeof(child_variant) != TYPE_DICTIONARY:
            continue
        var child: Dictionary = child_variant
        var node_type := String(child.get("node_type", ""))
        var item := _seed_tree.create_item(parent)
        if node_type == "token":
            item.set_text(0, "[%s]" % String(child.get("token", "")))
            item.set_text(1, String(child.get("display_name", child.get("strategy", ""))))
            item.set_text(2, String(child.get("seed", "")))
            if (child.get("errors", []) is Array) and not (child.get("errors", []) as Array).is_empty():
                _tint_row(item, _ERROR_TINT)
            _render_template_children(item, child.get("children", []))
        else:
            item.set_text(0, node_type.capitalize())
            item.set_text(1, String(child.get("template", "")))
            item.set_text(2, String(child.get("seed", "")))
            _render_template_children(item, child.get("children", []))

func _preview_button_label(status: String) -> Color:
    return Color(0.85, 1.0, 0.85, 1.0) if status == "success" else Color(1.0, 0.85, 0.85, 1.0)

func _on_preview_pressed() -> void:
    var controller := _get_controller()
    if controller == null:
        _show_preview_state({
            "status": "error",
            "message": "RNGProcessor controller unavailable.",
        })
        return
    if not _hybrid_panel.has_method("build_config_payload"):
        _show_preview_state({"status": "error", "message": "Hybrid panel unavailable."})
        return
    var payload_variant := _hybrid_panel.call("build_config_payload")
    if typeof(payload_variant) != TYPE_DICTIONARY:
        _show_preview_state({"status": "error", "message": "Failed to build hybrid payload."})
        return
    var payload: Dictionary = payload_variant
    var steps := payload.get("steps", [])
    if steps is Array and steps.is_empty():
        _show_preview_state({"status": "error", "message": "Configure at least one hybrid step."})
        return
    _inject_template_payload(steps)
    payload["steps"] = steps
    var response: Variant = controller.call("generate", payload)
    if response is Dictionary and response.has("code"):
        var error_dict: Dictionary = response
        _show_preview_state({
            "status": "error",
            "message": String(error_dict.get("message", "Generation failed.")),
        })
        return
    _show_preview_state({"status": "success", "message": String(response)})
    _rebuild_propagation_tree()

func _inject_template_payload(steps: Array) -> void:
    if not _blueprint_lookup.has(_current_blueprint_id):
        return
    var alias := String(_blueprint_lookup[_current_blueprint_id].get("template_step_alias", ""))
    if alias == "":
        return
    if not _template_panel.has_method("build_config_payload"):
        return
    var template_variant := _template_panel.call("build_config_payload")
    if typeof(template_variant) != TYPE_DICTIONARY:
        return
    var template_config: Dictionary = template_variant
    for index in range(steps.size()):
        var entry_variant := steps[index]
        if typeof(entry_variant) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_variant
        var entry_alias := String(entry.get("store_as", ""))
        var config_variant := entry.get("config", {})
        if alias != "" and entry_alias == alias:
            entry["config"] = template_config.duplicate(true)
            steps[index] = entry
            return
        if alias == "" and typeof(config_variant) == TYPE_DICTIONARY and String(config_variant.get("strategy", "")) == "template":
            entry["config"] = template_config.duplicate(true)
            steps[index] = entry
            return

func _show_preview_state(state: Dictionary) -> void:
    var status := String(state.get("status", ""))
    var message := String(state.get("message", ""))
    _preview_label.visible = true
    _preview_label.text = message
    _preview_label.self_modulate = _preview_button_label(status)

func _on_meta_clicked(meta: Variant) -> void:
    var target := String(meta)
    if target.begins_with("res://"):
        target = ProjectSettings.globalize_path(target)
    if target == "":
        return
    OS.shell_open(target)

func _tint_row(item: TreeItem, tint: Color) -> void:
    for column in range(_seed_tree.columns):
        item.set_custom_bg_color(column, tint)

func _build_reference_url(path: String, anchor: String) -> String:
    if anchor == "":
        return path
    if path.find("#") != -1:
        return path
    return "%s#%s" % [path, anchor]

func _get_controller() -> Object:
    if _controller_override != null and _is_object_valid(_controller_override):
        return _controller_override
    if _cached_controller != null and _is_object_valid(_cached_controller):
        return _cached_controller
    if controller_path != NodePath("") and has_node(controller_path):
        var node := get_node(controller_path)
        if node != null:
            _cached_controller = node
            return _cached_controller
    if Engine.has_singleton("RNGProcessorController"):
        var singleton := Engine.get_singleton("RNGProcessorController")
        if _is_object_valid(singleton):
            _cached_controller = singleton
            return _cached_controller
    return null

func _is_object_valid(candidate: Object) -> bool:
    if candidate == null:
        return false
    if candidate is Node:
        return is_instance_valid(candidate)
    return true
