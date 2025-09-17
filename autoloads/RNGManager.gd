extends Node
class_name RNGManager

## RNGManager centralizes deterministic random number generation across the project.
##
## Usage expectations:
## - Request named RNG streams via `get_rng("gameplay")` rather than instantiating
##   ad-hoc `RandomNumberGenerator` objects. Each stream is deterministically seeded
##   from the master seed combined with its name, so the same master seed reproduces
##   the same sequences.
## - Call `set_master_seed()` (or `randomize_master_seed()`) during initialization to
##   control reproducibility. Changing the master seed resets all cached streams.
## - Use `save_state()` / `load_state()` to serialize and restore the active RNG
##   states when saving or loading a game.

var _master_seed: int = 0
var _streams: Dictionary = {}

const _STATE_MASTER_SEED := "master_seed"
const _STATE_STREAMS := "streams"
const _STATE_SEED := "seed"
const _STATE_STATE := "state"

func set_master_seed(seed: int) -> void:
    _master_seed = seed
    for stream_name in _streams.keys():
        _initialize_stream(stream_name, _streams[stream_name])

func randomize_master_seed() -> void:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    set_master_seed(rng.randi())

func get_rng(stream_name: String) -> RandomNumberGenerator:
    if not _streams.has(stream_name):
        _streams[stream_name] = _create_stream(stream_name)
    return _streams[stream_name]

func save_state() -> Dictionary:
    var serialized_streams := {}
    for stream_name in _streams.keys():
        var rng: RandomNumberGenerator = _streams[stream_name]
        serialized_streams[stream_name] = {
            _STATE_SEED: rng.seed,
            _STATE_STATE: rng.state,
        }
    return {
        _STATE_MASTER_SEED: _master_seed,
        _STATE_STREAMS: serialized_streams,
    }

func load_state(data) -> void:
    if typeof(data) != TYPE_DICTIONARY:
        push_warning("RNGManager.load_state expected a Dictionary; received %s" % typeof(data))
        return

    var master_seed := data.get(_STATE_MASTER_SEED, null)
    if master_seed == null:
        push_warning("RNGManager.load_state missing master_seed; keeping current seed")
    else:
        set_master_seed(int(master_seed))

    var streams := data.get(_STATE_STREAMS, {})
    if typeof(streams) != TYPE_DICTIONARY:
        push_warning("RNGManager.load_state streams payload must be a Dictionary")
        return

    for stream_name in streams.keys():
        var stream_payload = streams[stream_name]
        if typeof(stream_payload) != TYPE_DICTIONARY:
            push_warning("RNGManager.load_state stream '%s' payload must be a Dictionary" % stream_name)
            continue

        var rng := get_rng(stream_name)
        if stream_payload.has(_STATE_SEED):
            rng.seed = int(stream_payload[_STATE_SEED])
        if stream_payload.has(_STATE_STATE):
            rng.state = int(stream_payload[_STATE_STATE])

func _create_stream(stream_name: String) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    _initialize_stream(stream_name, rng)
    return rng

func _initialize_stream(stream_name: String, rng: RandomNumberGenerator) -> void:
    var seed := _compute_stream_seed(stream_name)
    rng.seed = seed

func _compute_stream_seed(stream_name: String) -> int:
    var hashed := hash("%s::%s" % [_master_seed, stream_name])
    return int(hashed & 0x7fffffffffffffff)
