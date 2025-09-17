extends SceneTree

const RNGProcessor := preload("res://name_generator/RNGProcessor.gd")
const DebugRNG := preload("res://name_generator/tools/DebugRNG.gd")
const NameGeneratorScript := preload("res://name_generator/NameGenerator.gd")

const WORDLIST_PATH := "res://tests/test_assets/wordlist_basic.tres"
const SYLLABLE_PATH := "res://tests/test_assets/syllable_basic.tres"
const MARKOV_PATH := "res://tests/test_assets/markov_basic.tres"
const DEBUG_LOG_PATH := "user://debug_rng_processor_headless.txt"

var _processor: RNGProcessor
var _debug_rng: DebugRNG
var _failures: Array[Dictionary] = []
var _started_events: Array[Dictionary] = []
var _completed_events: Array[Dictionary] = []
var _failed_events: Array[Dictionary] = []

func _initialize() -> void:
    _processor = RNGProcessor.new()
    get_root().add_child(_processor)
    _processor._ready()

    _debug_rng = DebugRNG.new()
    _debug_rng.begin_session({
        "suite": "rng_processor_headless",
    })
    _debug_rng.attach_to_processor(_processor, DEBUG_LOG_PATH)

    _processor.connect("generation_started", Callable(self, "_on_generation_started"))
    _processor.connect("generation_completed", Callable(self, "_on_generation_completed"))
    _processor.connect("generation_failed", Callable(self, "_on_generation_failed"))

    call_deferred("_run")

func _run() -> void:

    _processor.initialize_master_seed(424242)
    _debug_rng.record_warning("Headless RNGProcessor scenarios starting.", {"suite": "rng_processor_headless"})

    _execute("wordlist_deterministic", func(): return _scenario_wordlist())
    _execute("syllable_deterministic", func(): return _scenario_syllable())
    _execute("markov_deterministic", func(): return _scenario_markov())
    _execute("hybrid_deterministic", func(): return _scenario_hybrid())
    _execute("missing_wordlist_paths", func(): return _scenario_missing_wordlist())
    _execute("unknown_strategy_error", func(): return _scenario_unknown_strategy())

    _debug_rng.record_warning("Headless RNGProcessor scenarios completed.", {"suite": "rng_processor_headless"})
    _debug_rng.close()

    _verify_signal_counts()
    _verify_debug_log()

    var exit_code = 0 if _failures.is_empty() else 1
    if exit_code != 0:
        for failure in _failures:
            var name = failure.get("name", "")
            var message = failure.get("message", "")
            push_error("[rng_processor_headless] %s -- %s" % [name, message])

    quit(exit_code)

func _execute(name: String, callable: Callable) -> void:
    var message = callable.call()
    if message == null:
        return
    _failures.append({
        "name": name,
        "message": String(message),
    })

func _scenario_wordlist() -> Variant:
    var config = {
        "strategy": "wordlist",
        "wordlist_paths": [WORDLIST_PATH],
        "use_weights": true,
        "seed": "headless_wordlist",
    }

    var expected = _expected_string(config)
    if expected is Dictionary:
        return "Expected NameGenerator to succeed for wordlist scenario: %s" % (expected as Dictionary).get("code", "")

    var result = _processor.generate(config)
    if result is Dictionary:
        return "Wordlist configuration should succeed but returned error code %s" % (result as Dictionary).get("code", "")

    if String(result) != String(expected):
        return "Wordlist result mismatch. Expected '%s' but received '%s'." % [expected, result]

    return null

func _scenario_syllable() -> Variant:
    var config = {
        "strategy": "syllable",
        "syllable_set_path": SYLLABLE_PATH,
        "seed": "headless_syllable",
        "require_middle": false,
    }

    var expected = _expected_string(config)
    if expected is Dictionary:
        return "Expected NameGenerator to succeed for syllable scenario: %s" % (expected as Dictionary).get("code", "")

    var result = _processor.generate(config)
    if result is Dictionary:
        return "Syllable configuration should succeed but returned error code %s" % (result as Dictionary).get("code", "")

    if String(result) != String(expected):
        return "Syllable result mismatch. Expected '%s' but received '%s'." % [expected, result]

    return null

func _scenario_markov() -> Variant:
    var config = {
        "strategy": "markov",
        "markov_model_path": MARKOV_PATH,
        "seed": "headless_markov",
    }

    var expected = _expected_string(config)
    if expected is Dictionary:
        return "Expected NameGenerator to succeed for markov scenario: %s" % (expected as Dictionary).get("code", "")

    var result = _processor.generate(config)
    if result is Dictionary:
        return "Markov configuration should succeed but returned error code %s" % (result as Dictionary).get("code", "")

    if String(result) != String(expected):
        return "Markov result mismatch. Expected '%s' but received '%s'." % [expected, result]

    return null

func _scenario_hybrid() -> Variant:
    var config = {
        "strategy": "hybrid",
        "seed": "headless_hybrid",
        "steps": [
            {
                "strategy": "wordlist",
                "wordlist_paths": [WORDLIST_PATH],
                "use_weights": true,
                "store_as": "title",
            },
            {
                "strategy": "markov",
                "markov_model_path": MARKOV_PATH,
                "store_as": "root",
            },
            {
                "strategy": "syllable",
                "syllable_set_path": SYLLABLE_PATH,
                "store_as": "suffix",
            },
        ],
        "template": "$title $root$suffix",
    }

    var expected = _expected_string(config)
    if expected is Dictionary:
        return "Expected NameGenerator to succeed for hybrid scenario: %s" % (expected as Dictionary).get("code", "")

    var result = _processor.generate(config)
    if result is Dictionary:
        return "Hybrid configuration should succeed but returned error code %s" % (result as Dictionary).get("code", "")

    if String(result) != String(expected):
        return "Hybrid result mismatch. Expected '%s' but received '%s'." % [expected, result]

    if String(result).find("$") != -1:
        return "Hybrid template placeholders should be resolved in the final output."

    return null

func _scenario_missing_wordlist() -> Variant:
    var config = {
        "strategy": "wordlist",
        "wordlist_paths": [],
        "seed": "headless_missing_wordlist",
    }

    var result = _processor.generate(config)
    if not (result is Dictionary):
        return "Missing wordlist configuration should surface an error dictionary."

    var error = result as Dictionary
    if error.get("code", "") != "wordlists_missing":
        return "Unexpected error code for missing wordlist paths: %s" % error.get("code", "")

    if not error.has("message") or String(error.get("message", "")).is_empty():
        return "Error dictionary must include a descriptive message."

    if not error.has("details") or typeof(error["details"]) != TYPE_DICTIONARY:
        return "Error dictionary must include a details payload."

    return null

func _scenario_unknown_strategy() -> Variant:
    var config = {
        "strategy": "does_not_exist",
        "seed": "headless_unknown_strategy",
    }

    var result = _processor.generate(config)
    if not (result is Dictionary):
        return "Unknown strategy configuration should surface an error dictionary."

    var error = result as Dictionary
    if error.get("code", "") != "unknown_strategy":
        return "Unexpected error code for unknown strategy: %s" % error.get("code", "")

    if not error.has("message") or String(error.get("message", "")).is_empty():
        return "Unknown strategy error should provide a message."

    return null

func _expected_string(config: Dictionary) -> Variant:
    var expected = _generate_expected_payload(config)
    if expected is Dictionary:
        return expected
    return String(expected)

func _generate_expected_payload(config: Dictionary) -> Variant:
    var generator = Engine.get_singleton("NameGenerator")
    if generator == null:
        return {"code": "missing_name_generator"}

    var strategy_id = String(config.get("strategy", "")).strip_edges()
    var stream_name = _derive_stream_name(config, strategy_id)
    var clone = _clone_stream_rng(stream_name)

    var duplicate_config = config.duplicate(true)
    return generator.generate(duplicate_config, clone)

func _derive_stream_name(config: Dictionary, strategy_id: String) -> String:
    if config.has("rng_stream"):
        return String(config["rng_stream"])

    if config.has("seed"):
        var seed_string = String(config["seed"]).strip_edges()
        if seed_string.is_empty():
            seed_string = "seed"
        return "%s::%s" % [strategy_id, seed_string]

    return "%s::%s" % [NameGeneratorScript.DEFAULT_STREAM_PREFIX, strategy_id]

func _clone_stream_rng(stream_name: String) -> RandomNumberGenerator:
    var source = _processor.get_rng(stream_name)
    var clone = RandomNumberGenerator.new()
    clone.seed = source.seed
    clone.state = source.state
    return clone

func _verify_signal_counts() -> void:
    var expected_started = 6
    var expected_completed = 4
    var expected_failed = 2

    if _started_events.size() != expected_started:
        _failures.append({
            "name": "signal_started_count",
            "message": "Expected %d generation_started events, observed %d." % [expected_started, _started_events.size()],
        })

    if _completed_events.size() != expected_completed:
        _failures.append({
            "name": "signal_completed_count",
            "message": "Expected %d generation_completed events, observed %d." % [expected_completed, _completed_events.size()],
        })

    if _failed_events.size() != expected_failed:
        _failures.append({
            "name": "signal_failed_count",
            "message": "Expected %d generation_failed events, observed %d." % [expected_failed, _failed_events.size()],
        })

func _verify_debug_log() -> void:
    if not FileAccess.file_exists(DEBUG_LOG_PATH):
        _failures.append({
            "name": "debug_log_exists",
            "message": "DebugRNG log was not written to %s" % DEBUG_LOG_PATH,
        })
        return

    var file = FileAccess.open(DEBUG_LOG_PATH, FileAccess.READ)
    if file == null:
        _failures.append({
            "name": "debug_log_open",
            "message": "Unable to open DebugRNG log at %s" % DEBUG_LOG_PATH,
        })
        return

    var report = file.get_as_text()
    var markers = [
        "wordlist::headless_wordlist",
        "syllable::headless_syllable",
        "markov::headless_markov",
        "hybrid::headless_hybrid",
        "does_not_exist::headless_unknown_strategy",
    ]

    for marker in markers:
        if report.find(marker) == -1:
            _failures.append({
                "name": "debug_log_marker_%s" % marker,
                "message": "DebugRNG report missing marker '%s'." % marker,
            })

func _on_generation_started(config: Dictionary, metadata: Dictionary) -> void:
    _started_events.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
    })

func _on_generation_completed(config: Dictionary, result: Variant, metadata: Dictionary) -> void:
    _completed_events.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
        "result": result,
    })

func _on_generation_failed(config: Dictionary, error: Dictionary, metadata: Dictionary) -> void:
    _failed_events.append({
        "config": config.duplicate(true),
        "metadata": metadata.duplicate(true),
        "error": error.duplicate(true),
    })
