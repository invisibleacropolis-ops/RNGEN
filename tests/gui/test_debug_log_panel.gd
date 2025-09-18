extends RefCounted

const PANEL_SCENE := preload("res://addons/platform_gui/panels/logs/DebugLogPanel.tscn")
const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()
    _run_test("renders_highlighted_sections", func(): _test_renders_highlighted_sections())
    _run_test("downloads_latest_report", func(): _test_downloads_latest_report())

    return {
        "suite": "Platform GUI Debug Log Panel",
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
    _failures.append({"name": name, "message": String(message)})

func _test_renders_highlighted_sections() -> Variant:
    var controller := ControllerStub.new()
    controller.debug_rng = _make_debug_rng_payload()

    var panel: Control = PANEL_SCENE.instantiate()
    panel.set_controller_override(controller)
    panel._ready()
    panel._on_refresh_pressed()

    var text := (panel.get_node("LogDisplay") as RichTextLabel).bbcode_text
    if text.find("⚠️") == -1:
        return "Warnings should be highlighted with the ⚠️ glyph."
    if text.find("‼") == -1:
        return "Strategy errors should be highlighted with the ‼ glyph."

    panel._on_section_selected(2) # warnings
    text = (panel.get_node("LogDisplay") as RichTextLabel).bbcode_text
    if text.find("⚠️") == -1 or text.find("stream=") != -1:
        return "Warnings filter should isolate warning entries."

    panel._on_section_selected(3) # stream usage
    text = (panel.get_node("LogDisplay") as RichTextLabel).bbcode_text
    if text.find("stream=") == -1:
        return "Stream usage filter should include stream telemetry entries."
    return null

func _test_downloads_latest_report() -> Variant:
    var controller := ControllerStub.new()
    var debug_rng := _make_debug_rng_payload()
    debug_rng.close()
    controller.debug_rng = debug_rng

    var panel: Control = PANEL_SCENE.instantiate()
    panel.set_controller_override(controller)
    panel._ready()
    panel._on_refresh_pressed()

    var target_path := "user://debug_rng_copy_test.txt"
    if FileAccess.file_exists(target_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(target_path))

    (panel.get_node("Header/DownloadPath") as LineEdit).text = target_path
    panel._on_download_pressed()

    if not FileAccess.file_exists(target_path):
        return "Download helper should write the DebugRNG report to disk."
    var expected := FileAccess.get_file_as_string(debug_rng.get_log_path())
    var actual := FileAccess.get_file_as_string(target_path)
    if expected != actual:
        return "Downloaded log should match the source DebugRNG report."

    DirAccess.remove_absolute(ProjectSettings.globalize_path(target_path))
    return null

func _make_debug_rng_payload() -> DebugRNG:
    var debug_rng := DebugRNG.new()
    debug_rng.begin_session({"label": "Test session"})
    debug_rng._on_generation_started({"strategy": "wordlist"}, {"strategy_id": "wordlist", "seed": "alpha", "rng_stream": "wordlist::default"})
    debug_rng._on_generation_failed({"strategy": "wordlist"}, {"code": "validation_error"}, {"strategy_id": "wordlist"})
    debug_rng.record_warning("Sample warning", {"context": "unit"})
    debug_rng.record_stream_usage("wordlist::default", {"details": "token"})
    debug_rng._on_strategy_error("invalid_config", "Strategy failed", {}, "wordlist")
    return debug_rng

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

class ControllerStub:
    extends Node

    var debug_rng: Object = null

    func get_debug_rng() -> Object:
        return debug_rng
