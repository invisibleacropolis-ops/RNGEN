extends Node

## Central manager that coordinates deterministic random number streams.
## The singleton exposes named RNG instances derived from a master seed so
## independent systems can share reproducible randomness without colliding.

var _master_seed: int = 0
var _streams: Dictionary = {}

const _STATE_MASTER_SEED := "master_seed"
const _STATE_STREAMS := "streams"
const _STATE_STATE := "state"
const _STATE_SEED := "seed"

func _ready() -> void:
    if _master_seed == 0:
        randomize_master_seed()

func set_master_seed(seed_value: int) -> void:
    _master_seed = seed_value
    _streams.clear()

func get_master_seed() -> int:
    return _master_seed

func randomize_master_seed() -> void:
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.randomize()
    set_master_seed(int(rng.randi()))

func get_rng(stream_name: String) -> RandomNumberGenerator:
    var name: String = stream_name
    if name.is_empty():
        name = "default"

    if not _streams.has(name):
        _streams[name] = _create_stream(name)

    return _streams[name]

func save_state() -> Dictionary:
    var serialized: Dictionary = {}
    for key in _streams.keys():
        var rng: RandomNumberGenerator = _streams[key]
        serialized[key] = {
            _STATE_SEED: int(rng.seed),
            _STATE_STATE: int(rng.state),
        }
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

    if not (data[_STATE_STREAMS] is Dictionary):
        push_warning("RNGManager.load_state streams payload must be a Dictionary.")
        return

    var streams: Dictionary = data[_STATE_STREAMS]
    for key in streams.keys():
        var rng: RandomNumberGenerator = get_rng(String(key))
        _apply_stream_payload(rng, key, streams[key])

func randf(stream_name: String = "utility") -> float:
    return get_rng(stream_name).randf()

func randi_range(stream_name: String, minimum: int, maximum: int) -> int:
    return get_rng(stream_name).randi_range(minimum, maximum)

func _create_stream(name: String) -> RandomNumberGenerator:
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    var seed: int = _compute_stream_seed(name)
    rng.seed = seed
    rng.state = seed
    return rng

func _compute_stream_seed(name: String) -> int:
    var hashed: int = hash("%s::%s" % [_master_seed, name])
    return int(hashed & 0x7fffffffffffffff)

func _apply_stream_payload(rng: RandomNumberGenerator, stream_name: String, payload: Variant) -> void:
    if typeof(payload) in [TYPE_INT, TYPE_FLOAT]:
        var value := int(payload)
        rng.seed = value
        rng.state = value
        return

    if typeof(payload) != TYPE_DICTIONARY:
        push_warning("RNGManager.load_state stream '%s' payload must be an integer or dictionary." % stream_name)
        return

    var data: Dictionary = payload

    var seed_value: Variant = data.get(_STATE_SEED, null)
    var state_value: Variant = data.get(_STATE_STATE, null)
    var seed_applied: bool = false
    var state_applied: bool = false

    if typeof(seed_value) in [TYPE_INT, TYPE_FLOAT]:
        rng.seed = int(seed_value)
        seed_applied = true
    elif data.has(_STATE_SEED):
        push_warning("RNGManager.load_state stream '%s' seed must be numeric." % stream_name)

    if typeof(state_value) in [TYPE_INT, TYPE_FLOAT]:
        rng.state = int(state_value)
        state_applied = true
    elif data.has(_STATE_STATE):
        push_warning("RNGManager.load_state stream '%s' state must be numeric." % stream_name)

    if not state_applied and seed_applied:
        rng.state = int(seed_value)
        state_applied = true

    if not seed_applied and not state_applied:
        push_warning("RNGManager.load_state stream '%s' payload did not contain valid seed or state values." % stream_name)
