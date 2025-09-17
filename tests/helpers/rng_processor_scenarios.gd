extends RefCounted

## Shared RNGProcessor headless scenarios used by both the legacy SceneTree-based
## integration test and the single-script diagnostic harness. The helper keeps
## scenario configuration data and validation logic in one place so changes to
## expected behaviour remain consistent across both entry points.

const NameGeneratorScript := preload("res://name_generator/NameGenerator.gd")

const WORDLIST_PATH := "res://tests/test_assets/wordlist_basic.tres"
const SYLLABLE_PATH := "res://tests/test_assets/syllable_basic.tres"
const MARKOV_PATH := "res://tests/test_assets/markov_basic.tres"

static func collect_default_scenarios(processor: RNGProcessor) -> Array[Dictionary]:
    ## Build the canonical list of deterministic scenarios exercised by the
    ## headless suite. Each entry exposes a `name` identifier paired with a
    ## callable that returns `null` on success or an error string describing the
    ## failure context.
    return [
        _scenario_entry("wordlist_deterministic", func(): return scenario_wordlist(processor)),
        _scenario_entry("syllable_deterministic", func(): return scenario_syllable(processor)),
        _scenario_entry("markov_deterministic", func(): return scenario_markov(processor)),
        _scenario_entry("hybrid_deterministic", func(): return scenario_hybrid(processor)),
        _scenario_entry("missing_wordlist_paths", func(): return scenario_missing_wordlist(processor)),
        _scenario_entry("unknown_strategy_error", func(): return scenario_unknown_strategy(processor)),
    ]

static func scenario_wordlist(processor: RNGProcessor) -> Variant:
    var config := {
        "strategy": "wordlist",
        "wordlist_paths": [WORDLIST_PATH],
        "use_weights": true,
        "seed": "headless_wordlist",
    }
    return _validate_successful_result(processor, config, "wordlist")["message"]

static func scenario_syllable(processor: RNGProcessor) -> Variant:
    var config := {
        "strategy": "syllable",
        "syllable_set_path": SYLLABLE_PATH,
        "seed": "headless_syllable",
        "require_middle": false,
    }
    return _validate_successful_result(processor, config, "syllable")["message"]

static func scenario_markov(processor: RNGProcessor) -> Variant:
    var config := {
        "strategy": "markov",
        "markov_model_path": MARKOV_PATH,
        "seed": "headless_markov",
    }
    return _validate_successful_result(processor, config, "markov")["message"]

static func scenario_hybrid(processor: RNGProcessor) -> Variant:
    var config := {
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

    var evaluation := _validate_successful_result(processor, config, "hybrid")
    var message := evaluation.get("message", null)
    if message != null:
        return message

    var result_text := String(evaluation.get("result", ""))
    if result_text.find("$") != -1:
        return "Hybrid template placeholders should be resolved in the final output."

    return null

static func scenario_missing_wordlist(processor: RNGProcessor) -> Variant:
    var config := {
        "strategy": "wordlist",
        "wordlist_paths": [],
        "seed": "headless_missing_wordlist",
    }

    var result := processor.generate(config)
    if not (result is Dictionary):
        return "Missing wordlist configuration should surface an error dictionary."

    var error := result as Dictionary
    if error.get("code", "") != "wordlists_missing":
        return "Unexpected error code for missing wordlist paths: %s" % error.get("code", "")

    if not error.has("message") or String(error.get("message", "")).is_empty():
        return "Error dictionary must include a descriptive message."

    if not error.has("details") or typeof(error["details"]) != TYPE_DICTIONARY:
        return "Error dictionary must include a details payload."

    return null

static func scenario_unknown_strategy(processor: RNGProcessor) -> Variant:
    var config := {
        "strategy": "does_not_exist",
        "seed": "headless_unknown_strategy",
    }

    var result := processor.generate(config)
    if not (result is Dictionary):
        return "Unknown strategy configuration should surface an error dictionary."

    var error := result as Dictionary
    if error.get("code", "") != "unknown_strategy":
        return "Unexpected error code for unknown strategy: %s" % error.get("code", "")

    if not error.has("message") or String(error.get("message", "")).is_empty():
        return "Unknown strategy error should provide a message."

    return null

static func expected_signal_counts() -> Dictionary:
    return {
        "started": 6,
        "completed": 4,
        "failed": 2,
    }

static func debug_log_markers() -> PackedStringArray:
    var markers := PackedStringArray()
    markers.append("wordlist::headless_wordlist")
    markers.append("syllable::headless_syllable")
    markers.append("markov::headless_markov")
    markers.append("hybrid::headless_hybrid")
    markers.append("does_not_exist::headless_unknown_strategy")
    return markers

static func evaluate_signal_counts(
    started_events: Array,
    completed_events: Array,
    failed_events: Array
) -> Array[Dictionary]:
    var failures: Array[Dictionary] = []
    var expectations := expected_signal_counts()

    var expected_started := int(expectations.get("started", 0))
    if started_events.size() != expected_started:
        failures.append({
            "name": "signal_started_count",
            "message": "Expected %d generation_started events, observed %d." % [expected_started, started_events.size()],
        })

    var expected_completed := int(expectations.get("completed", 0))
    if completed_events.size() != expected_completed:
        failures.append({
            "name": "signal_completed_count",
            "message": "Expected %d generation_completed events, observed %d." % [expected_completed, completed_events.size()],
        })

    var expected_failed := int(expectations.get("failed", 0))
    if failed_events.size() != expected_failed:
        failures.append({
            "name": "signal_failed_count",
            "message": "Expected %d generation_failed events, observed %d." % [expected_failed, failed_events.size()],
        })

    return failures

static func evaluate_debug_log(report_path: String, markers: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
    var failures: Array[Dictionary] = []
    var expected_markers := markers if markers.size() > 0 else debug_log_markers()

    if not FileAccess.file_exists(report_path):
        failures.append({
            "name": "debug_log_exists",
            "message": "DebugRNG log was not written to %s" % report_path,
        })
        return failures

    var file := FileAccess.open(report_path, FileAccess.READ)
    if file == null:
        failures.append({
            "name": "debug_log_open",
            "message": "Unable to open DebugRNG log at %s" % report_path,
        })
        return failures

    var report := file.get_as_text()
    for marker in expected_markers:
        if report.find(marker) == -1:
            failures.append({
                "name": "debug_log_marker_%s" % marker,
                "message": "DebugRNG report missing marker '%s'." % marker,
            })

    return failures

static func expected_string(processor: RNGProcessor, config: Dictionary) -> Variant:
    var expected := _generate_expected_payload(processor, config)
    if expected is Dictionary:
        return expected
    return String(expected)

static func _generate_expected_payload(processor: RNGProcessor, config: Dictionary) -> Variant:
    var generator := Engine.get_singleton("NameGenerator")
    if generator == null:
        return {"code": "missing_name_generator"}

    var strategy_id := String(config.get("strategy", "")).strip_edges()
    var stream_name := _derive_stream_name(config, strategy_id)
    var clone := _clone_stream_rng(processor, stream_name)

    var duplicate_config := config.duplicate(true)
    return generator.generate(duplicate_config, clone)

static func _derive_stream_name(config: Dictionary, strategy_id: String) -> String:
    if config.has("rng_stream"):
        return String(config["rng_stream"])

    if config.has("seed"):
        var seed_string := String(config["seed"]).strip_edges()
        if seed_string.is_empty():
            seed_string = "seed"
        return "%s::%s" % [strategy_id, seed_string]

    return "%s::%s" % [NameGeneratorScript.DEFAULT_STREAM_PREFIX, strategy_id]

static func _clone_stream_rng(processor: RNGProcessor, stream_name: String) -> RandomNumberGenerator:
    var source := processor.get_rng(stream_name)
    var clone := RandomNumberGenerator.new()
    clone.seed = source.seed
    clone.state = source.state
    return clone

static func _scenario_entry(name: String, callable: Callable) -> Dictionary:
    return {
        "name": name,
        "callable": callable,
    }

static func _validate_successful_result(processor: RNGProcessor, config: Dictionary, label: String) -> Dictionary:
    var expected := expected_string(processor, config)
    if expected is Dictionary:
        return {
            "message": "Expected NameGenerator to succeed for %s scenario: %s" % [label, (expected as Dictionary).get("code", "")],
            "result": null,
            "expected": expected,
        }

    var expected_text := String(expected)
    var result := processor.generate(config)
    if result is Dictionary:
        return {
            "message": "%s configuration should succeed but returned error code %s" % [label.capitalize(), (result as Dictionary).get("code", "")],
            "result": result,
            "expected": expected_text,
        }

    var result_text := String(result)
    if result_text != expected_text:
        return {
            "message": "%s result mismatch. Expected '%s' but received '%s'." % [label.capitalize(), expected_text, result_text],
            "result": result,
            "expected": expected_text,
        }

    return {
        "message": null,
        "result": result,
        "expected": expected_text,
    }
