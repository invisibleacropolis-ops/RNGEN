extends RefCounted

const SERVICE_SCRIPT := preload("res://addons/platform_gui/services/strategy_metadata.gd")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()

    _run_test("caches_strategy_metadata", func(): _test_caches_strategy_metadata())
    _run_test("exposes_lookup_helpers", func(): _test_exposes_lookup_helpers())
    _run_test("provides_plain_language_error_hints", func(): _test_provides_plain_language_error_hints())
    _run_test("refreshes_metadata_on_demand", func(): _test_refreshes_metadata_on_demand())

    return {
        "suite": "Platform GUI Strategy Metadata Service",
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

func _test_caches_strategy_metadata() -> Variant:
    var controller := StubController.new()
    controller.metadata = _make_metadata_payload()
    var service := _make_service(controller)

    var first := service.get_strategy_metadata("wordlist")
    var second := service.get_strategy_metadata("wordlist")
    if controller.describe_calls != 1:
        return "Service should cache controller responses between lookups."

    first["display_name"] = "mutated"
    var third := service.get_strategy_metadata("wordlist")
    if third.get("display_name", "") == "mutated":
        return "Strategy metadata accessors must provide defensive copies."

    if service.get_strategy_ids().size() != 2:
        return "Service should report every available strategy identifier."

    return null

func _test_exposes_lookup_helpers() -> Variant:
    var controller := StubController.new()
    controller.metadata = _make_metadata_payload()
    var service := _make_service(controller)

    var required := service.get_required_keys("wordlist")
    if required.size() != 1 or required[0] != "wordlist_paths":
        return "Required keys helper should normalise the schema payload."

    var optional := service.get_optional_key_types("wordlist")
    if optional.size() != 2:
        return "Optional key helper should surface the expected type map."
    if int(optional.get("delimiter", -1)) != TYPE_STRING:
        return "Optional key helper should preserve variant type constants."

    var notes := service.get_default_notes("template")
    if notes.size() != 1 or not notes[0].begins_with("Template note"):
        return "Default notes helper should normalise PackedStringArray payloads."

    var unknown_required := service.get_required_keys("missing")
    if not unknown_required.is_empty():
        return "Unknown strategy lookups should return empty required key sets."

    return null

func _test_provides_plain_language_error_hints() -> Variant:
    var controller := StubController.new()
    controller.metadata = _make_metadata_payload()
    var service := _make_service(controller)

    var hints := service.get_generator_error_hints("wordlist")
    if not hints.has("missing_required_keys"):
        return "Error hints should include schema-derived missing key guidance."
    if String(hints["missing_required_keys"]).find("wordlist_paths") == -1:
        return "Missing key hint should reference the required configuration keys."

    if not hints.has("invalid_key_type"):
        return "Error hints should include optional key type guidance."
    if String(hints["invalid_key_type"]).find("delimiter") == -1:
        return "Type hint should reference optional configuration keys."
    if String(hints["invalid_key_type"]).find("String") == -1:
        return "Type hint should surface human-readable type names."

    var base_hint := service.get_generator_error_hint("wordlist", "invalid_config_type")
    if base_hint.find("Dictionary") == -1:
        return "Shared schema hints should surface descriptive default messages."

    var unknown_hint := service.get_generator_error_hint("missing", "invalid_config_type")
    if unknown_hint == "":
        return "Unknown strategies should still expose shared schema hints."

    return null

func _test_refreshes_metadata_on_demand() -> Variant:
    var controller := StubController.new()
    controller.metadata = _make_metadata_payload()
    var service := _make_service(controller)

    if service.get_generator_error_hint("template", "missing_required_keys").find("template_string") == -1:
        return "Initial metadata load should describe the template strategy requirements."

    controller.metadata = {
        "template": {
            "id": "template",
            "expected_config": {
                "required": PackedStringArray(["template_string", "sub_generators"]),
            },
        },
    }

    service.refresh_metadata()

    var refreshed := service.get_required_keys("template")
    if refreshed.size() != 2 or refreshed[1] != "template_string":
        return "Refresh should replace the cached metadata payload."
    if controller.describe_calls != 2:
        return "Refresh must trigger a new controller describe_strategies call."

    return null

func _make_service(controller: StubController) -> Object:
    var instance: Node = SERVICE_SCRIPT.new()
    instance.set_controller_override(controller)
    return instance

func _make_metadata_payload() -> Dictionary:
    return {
        "wordlist": {
            "id": "wordlist",
            "display_name": "Word List",
            "expected_config": {
                "required": PackedStringArray(["wordlist_paths"]),
                "optional": {
                    "delimiter": TYPE_STRING,
                    "use_weights": TYPE_BOOL,
                },
            },
            "notes": PackedStringArray(["Wordlist note guidance."]),
        },
        "template": {
            "id": "template",
            "display_name": "Template",
            "expected_config": {
                "required": PackedStringArray(["template_string"]),
            },
            "notes": ["Template note details."],
        },
    }

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

class StubController:
    extends Node

    var describe_calls: int = 0
    var metadata: Dictionary = {}

    func describe_strategies() -> Dictionary:
        describe_calls += 1
        return metadata.duplicate(true)
