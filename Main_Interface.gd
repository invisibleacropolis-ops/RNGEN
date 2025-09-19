extends Control

## Top-level scene that wires together the Platform GUI middleware and editor panels.
##
## The node instantiates local copies of the controller, metadata service, and
## event bus so engineers can launch the interface in isolation without relying
## on global autoloads. When the scene is ready, the middleware nodes are
## registered as singletons and injected into every toolbar, panel, and workspace
## so they immediately bind to live middleware state. This mirrors the runtime
## environment shipped with the add-on while keeping the editor hierarchy fully
## self-contained for tests and tooling.

const _RNG_PROCESSOR_SINGLETON := StringName("RNGProcessor")
const _RNGProcessor := preload("res://name_generator/RNGProcessor.gd")

@onready var _event_bus: Node = $EventBus
@onready var _controller: Node = $ProcessorController
@onready var _metadata_service: Node = $StrategyMetadataService
@onready var _middleware_consumers: Array = [
	%DebugToolbar,
	%WordlistPanel,
	%SyllableChainPanel,
	%TemplatePanel,
	%MarkovPanel,
	%HybridPipelinePanel,
	%SeedsDashboardPanel,
	%DebugLogPanel,
	%DatasetInspectorPanel,
	%QAPanel,
	%FormulasWorkspace,
]

var _registered_singletons: Array = []
var _local_rng_processor: Node = null

func _ready() -> void:
	## Register middleware singletons and cascade overrides to the UI components.
	_ensure_rng_processor_singleton()
	_register_singleton("PlatformGUIEventBus", _event_bus)
	_register_singleton("RNGProcessorController", _controller)
	_register_singleton("StrategyMetadataService", _metadata_service)

	if is_instance_valid(_controller) and _controller.has_method("set_event_bus_override"):
		_controller.call("set_event_bus_override", _event_bus)
	if is_instance_valid(_metadata_service) and _metadata_service.has_method("set_controller_override"):
		_metadata_service.call("set_controller_override", _controller)

	for consumer in _middleware_consumers:
		if consumer == null:
			continue
		if consumer.has_method("set_controller_override"):
			consumer.call("set_controller_override", _controller)
		if consumer.has_method("set_metadata_service_override"):
			consumer.call("set_metadata_service_override", _metadata_service)
		if consumer.has_method("refresh"):
			consumer.call("refresh")

func _exit_tree() -> void:
	## Clean up registered singletons when the scene is removed from the tree.
	for entry in _registered_singletons:
		var name: StringName = entry.get("name", StringName())
		var node: Object = entry.get("node")
		if name == StringName():
			continue
		if Engine.has_singleton(name) and Engine.get_singleton(name) == node:
			Engine.unregister_singleton(name)
	_registered_singletons.clear()
	if is_instance_valid(_local_rng_processor):
		_local_rng_processor.queue_free()
	_local_rng_processor = null

func _register_singleton(name: StringName, node: Object) -> void:
	## Register the provided node as a singleton if the slot is free.
	if not is_instance_valid(node):
		push_warning("Attempted to register an invalid singleton: %s" % name)
		return
	if Engine.has_singleton(name):
		return
	Engine.register_singleton(name, node)
	_registered_singletons.append({
		"name": name,
		"node": node,
	})

func _ensure_rng_processor_singleton() -> void:
	## Instantiate a local RNGProcessor when the autoload is unavailable.
	if Engine.has_singleton(_RNG_PROCESSOR_SINGLETON):
		return
	_local_rng_processor = _RNGProcessor.new()
	add_child(_local_rng_processor)
	_register_singleton(_RNG_PROCESSOR_SINGLETON, _local_rng_processor)
