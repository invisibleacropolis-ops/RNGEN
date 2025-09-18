extends RefCounted

const INTERFACE_SCENE := preload("res://Main_Interface.tscn")
const EXPECTED_TAB_TITLES := [
    "Generators",
    "Seeds",
    "Debug Logs",
    "Dataset Health",
    "QA",
    "Formulas",
]
const _SINGLETON_NAMES := [
    StringName("PlatformGUIEventBus"),
    StringName("RNGProcessorController"),
    StringName("StrategyMetadataService"),
]

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _reset()
    _run_test("registers_middleware_singletons", func(): _test_registers_middleware_singletons())
    _run_test("propagates_controller_and_metadata_overrides", func(): _test_propagates_controller_and_metadata_overrides())
    _run_test("exposes_expected_tabs", func(): _test_exposes_expected_tabs())

    return {
        "suite": "Main Interface Scene",
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

func _test_registers_middleware_singletons() -> Variant:
    return _with_interface(func(interface: Control):
        var controller_name := StringName("RNGProcessorController")
        if not Engine.has_singleton(controller_name):
            return "Interface should register the RNGProcessorController singleton during _ready()."
        if Engine.get_singleton(controller_name) != interface._controller:
            return "Registered RNGProcessorController should reference the scene controller instance."

        var metadata_name := StringName("StrategyMetadataService")
        if not Engine.has_singleton(metadata_name):
            return "Interface should register the StrategyMetadataService singleton during _ready()."
        if Engine.get_singleton(metadata_name) != interface._metadata_service:
            return "Registered StrategyMetadataService should reference the scene service instance."

        var event_bus_name := StringName("PlatformGUIEventBus")
        if not Engine.has_singleton(event_bus_name):
            return "Interface should register the PlatformGUIEventBus singleton during _ready()."
        if Engine.get_singleton(event_bus_name) != interface._event_bus:
            return "Registered PlatformGUIEventBus should reference the scene event bus instance."

        return null
    )

func _test_propagates_controller_and_metadata_overrides() -> Variant:
    return _with_interface(func(interface: Control):
        var controller := interface._controller
        var metadata_service := interface._metadata_service
        for consumer in interface._middleware_consumers:
            if consumer == null:
                continue
            if consumer.has_method("_get_controller"):
                var resolved_controller := consumer.call("_get_controller")
                if resolved_controller != controller:
                    return "%s should resolve the shared RNGProcessorController instance." % consumer.name
            elif consumer.has_method("get_controller_override"):
                var resolved_override := consumer.call("get_controller_override")
                if resolved_override != controller:
                    return "%s should expose the shared RNGProcessorController override." % consumer.name

            if consumer.has_method("_get_metadata_service"):
                var resolved_service := consumer.call("_get_metadata_service")
                if resolved_service != metadata_service:
                    return "%s should resolve the shared StrategyMetadataService instance." % consumer.name
            elif consumer.has_method("get_metadata_service_override"):
                var resolved_metadata_override := consumer.call("get_metadata_service_override")
                if resolved_metadata_override != metadata_service:
                    return "%s should expose the shared StrategyMetadataService override." % consumer.name
        return null
    )

func _test_exposes_expected_tabs() -> Variant:
    return _with_interface(func(interface: Control):
        var main_tabs := interface.get_node("MainLayout/MainTabs") as TabContainer
        if main_tabs == null:
            return "MainTabs TabContainer should exist under the main layout."
        var visible_titles: Array[String] = []
        var tab_count := main_tabs.get_tab_count()
        for index in range(tab_count):
            if main_tabs.is_tab_hidden(index):
                continue
            visible_titles.append(main_tabs.get_tab_title(index))
        if visible_titles.size() < EXPECTED_TAB_TITLES.size():
            return "MainTabs should expose at least %d tabs." % EXPECTED_TAB_TITLES.size()
        for index in range(EXPECTED_TAB_TITLES.size()):
            var expected := EXPECTED_TAB_TITLES[index]
            var actual := visible_titles[index]
            if actual != expected:
                return "Tab title mismatch at index %d. Expected \"%s\" but found \"%s\"." % [index, expected, actual]
        return null
    )

func _with_interface(callable: Callable) -> Variant:
    var preserved := _unregister_conflicting_singletons()
    var interface := INTERFACE_SCENE.instantiate() as Control
    interface._ready()
    var message := callable.call(interface)
    _cleanup_interface(interface)
    _restore_singletons(preserved)
    return message

func _unregister_conflicting_singletons() -> Dictionary:
    var preserved: Dictionary = {}
    for name in _SINGLETON_NAMES:
        if Engine.has_singleton(name):
            preserved[name] = Engine.get_singleton(name)
            Engine.unregister_singleton(name)
    return preserved

func _cleanup_interface(interface: Control) -> void:
    if interface == null:
        return
    interface._exit_tree()
    interface.free()
    for name in _SINGLETON_NAMES:
        if Engine.has_singleton(name):
            Engine.unregister_singleton(name)

func _restore_singletons(preserved: Dictionary) -> void:
    for name in _SINGLETON_NAMES:
        if preserved.has(name):
            var node := preserved[name]
            if node != null and not Engine.has_singleton(name):
                Engine.register_singleton(name, node)

func _reset() -> void:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()
