extends Node
class_name RNGManager

## Central manager that coordinates deterministic random number streams.
## The singleton exposes named RNG instances derived from a master seed so
## independent systems can share reproducible randomness without colliding.

var _master_seed: int = 0
var _streams: Dictionary = {}

const _STATE_MASTER_SEED := "master_seed"
const _STATE_STREAMS := "streams"
const _STATE_STATE := "state"

func _ready() -> void:
    if _master_seed == 0:
        randomize_master_seed()

func set_master_seed(seed_value: int) -> void:
    _master_seed = seed_value
    _streams.clear()

func get_master_seed() -> int:
    return _master_seed

func randomize_master_seed() -> void:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    set_master_seed(int(rng.randi()))

func get_rng(stream_name: String) -> RandomNumberGenerator:
    var name := stream_name
    if name.is_empty():
        name = "default"

    if not _streams.has(name):
        _streams[name] = _create_stream(name)

    return _streams[name]

func save_state() -> Dictionary:
    var serialized := {}
    for key in _streams.keys():
        var rng: RandomNumberGenerator = _streams[key]
        serialized[key] = rng.state
    return {
        _STATE_MASTER_SEED: _master_seed,
        _STATE_STREAMS: serialized,
    }

func load_state(payload: Variant) -> void:
    if typeof(payload) != TYPE_DICTIONARY:
        push_warning("RNGManager.load_state expected a Dictionary payload.")
        return

    var data: Dictionary = payload
    if data.has(_STATE_MASTER_SEED):
        set_master_seed(int(data[_STATE_MASTER_SEED]))

    if not data.has(_STATE_STREAMS):
        return

    var streams := data[_STATE_STREAMS]
    if typeof(streams) != TYPE_DICTIONARY:
        push_warning("RNGManager.load_state streams payload must be a Dictionary.")
        return

    for key in streams.keys():
        var rng := get_rng(String(key))
        rng.state = int(streams[key])

func randf(stream_name: String = "utility") -> float:
    return get_rng(stream_name).randf()

func randi_range(stream_name: String, minimum: int, maximum: int) -> int:
    return get_rng(stream_name).randi_range(minimum, maximum)

func _create_stream(name: String) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    var seed := _compute_stream_seed(name)
    rng.seed = seed
    rng.state = seed
    return rng

func _compute_stream_seed(name: String) -> int:
    var hashed := hash("%s::%s" % [_master_seed, name])
    return int(hashed & 0x7fffffffffffffff)
