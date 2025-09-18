extends RefCounted

const WordlistStrategy := preload("res://name_generator/strategies/WordlistStrategy.gd")
const GeneratorStrategy := preload("res://name_generator/strategies/GeneratorStrategy.gd")
const ArrayUtils := preload("res://name_generator/utils/ArrayUtils.gd")
const WordListResource := preload("res://name_generator/resources/WordListResource.gd")

const WORDLIST_PATH := "res://tests/test_assets/wordlist_basic.tres"
const INVALID_RESOURCE_PATH := "res://tests/test_assets/syllable_basic.tres"
const MISSING_RESOURCE_PATH := "res://tests/test_assets/missing_wordlist.tres"

var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _checks.clear()

    _record("generate_uniform_respects_seed", func(): return _test_generate_uniform_success())
    _record("generate_weighted_respects_seed", func(): return _test_generate_weighted_success())
    _record("error_wordlists_missing", func(): return _test_wordlists_missing_error())
    _record("error_wordlist_load_failed", func(): return _test_wordlist_load_failed_error())
    _record("error_wordlist_invalid_type", func(): return _test_wordlist_invalid_type_error())
    _record("error_wordlist_empty", func(): return _test_wordlist_empty_error())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    return {
        "id": "wordlist_strategy",
        "name": "Wordlist strategy coverage diagnostic",
        "total": _checks.size(),
        "passed": _checks.size() - failures.size(),
        "failed": failures.size(),
        "failures": failures.duplicate(true),
    }

func _record(name: String, callable: Callable) -> void:
    var result = callable.call()
    var success := result == null
    _checks.append({
        "name": name,
        "success": success,
        "message": "" if success else String(result),
    })

func _test_generate_uniform_success() -> Variant:
    var resource := _load_wordlist_fixture()
    if resource == null:
        return "Fixture word list could not be loaded from %s." % WORDLIST_PATH

    var entries := resource.get_uniform_entries()
    if entries.is_empty():
        return "Fixture word list must expose uniform entries."

    var config := {
        "wordlist_paths": [WORDLIST_PATH],
        "delimiter": " ",
    }

    var seed := 424242
    var first := _generate_with_seed(config, seed)
    if first is GeneratorStrategy.GeneratorError:
        return "Expected uniform generation to succeed but received %s." % (first as GeneratorStrategy.GeneratorError).code

    if typeof(first) != TYPE_STRING or String(first).is_empty():
        return "Uniform generation should return a non-empty string."

    var expected_rng := RandomNumberGenerator.new()
    expected_rng.seed = seed
    var expected := ArrayUtils.pick_uniform(entries, expected_rng)
    if first != expected:
        return "Uniform generation must match ArrayUtils.pick_uniform for a seeded RNG."

    var repeat := _generate_with_seed(config, seed)
    if repeat != first:
        return "Identical seeds should reproduce the same uniform selection."

    return null

func _test_generate_weighted_success() -> Variant:
    var resource := _load_wordlist_fixture()
    if resource == null:
        return "Fixture word list could not be loaded from %s." % WORDLIST_PATH

    if not resource.has_weight_data():
        return "Fixture word list must provide weighted data for this diagnostic."

    var weighted_entries := resource.get_weighted_entries()
    if weighted_entries.is_empty():
        return "Weighted entries should not be empty when weight data is advertised."

    var config := {
        "wordlist_paths": [WORDLIST_PATH],
        "use_weights": true,
    }

    var seed := 987654
    var first := _generate_with_seed(config, seed)
    if first is GeneratorStrategy.GeneratorError:
        return "Expected weighted generation to succeed but received %s." % (first as GeneratorStrategy.GeneratorError).code

    if typeof(first) != TYPE_STRING or String(first).is_empty():
        return "Weighted generation should produce a non-empty string."

    var expected_rng := RandomNumberGenerator.new()
    expected_rng.seed = seed
    var expected := ArrayUtils.pick_weighted(weighted_entries, expected_rng)
    if first != expected:
        return "Weighted generation must honour ArrayUtils.pick_weighted for a seeded RNG."

    var repeat := _generate_with_seed(config, seed)
    if repeat != first:
        return "Identical seeds should reproduce the same weighted selection."

    return null

func _test_wordlists_missing_error() -> Variant:
    var config := {
        "wordlist_paths": [],
    }

    var result := _generate_with_seed(config, 123)
    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected missing paths to return a GeneratorError."

    var error := result as GeneratorStrategy.GeneratorError
    if error.code != WordlistStrategy.ERROR_NO_PATHS:
        return "Unexpected error code for missing paths: %s" % error.code

    if error.message.find("No word list resources") == -1:
        return "Missing paths error should describe the absence of resources."

    return null

func _test_wordlist_load_failed_error() -> Variant:
    var config := {
        "wordlist_paths": [MISSING_RESOURCE_PATH],
    }

    var result := _generate_with_seed(config, 456)
    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected missing resource to surface a GeneratorError."

    var error := result as GeneratorStrategy.GeneratorError
    if error.code != "missing_resource":
        return "Unexpected error code for missing resource: %s" % error.code

    if not String(error.message).begins_with("Missing resource"):
        return "Missing resource error should use the standardised message prefix."

    if error.details.get("path", "") == "":
        return "Load failure error should include the missing path in details."

    return null

func _test_wordlist_invalid_type_error() -> Variant:
    var config := {
        "wordlist_paths": [INVALID_RESOURCE_PATH],
    }

    var result := _generate_with_seed(config, 789)
    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected invalid resource type to return a GeneratorError."

    var error := result as GeneratorStrategy.GeneratorError
    if error.code != WordlistStrategy.ERROR_INVALID_RESOURCE:
        return "Unexpected error code for invalid resource type: %s" % error.code

    if error.message.find("must be a WordListResource") == -1:
        return "Invalid resource type error should mention the expected WordListResource type."

    if error.details.get("path", "") != INVALID_RESOURCE_PATH:
        return "Invalid resource type error should reference the offending path."

    return null

func _test_wordlist_empty_error() -> Variant:
    var empty_resource := WordListResource.new()
    var config := {
        "wordlist_paths": [empty_resource],
    }

    var result := _generate_with_seed(config, 321)
    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected empty resources to surface a GeneratorError."

    var error := result as GeneratorStrategy.GeneratorError
    if error.code != WordlistStrategy.ERROR_EMPTY_RESOURCE:
        return "Unexpected error code for empty word list: %s" % error.code

    if error.message.find("is empty") == -1:
        return "Empty resource error should mention the lack of entries."

    return null

func _generate_with_seed(config: Dictionary, seed: int) -> Variant:
    var strategy := WordlistStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = seed
    return strategy.generate(config.duplicate(true), rng)

func _load_wordlist_fixture() -> WordListResource:
    var resource := ResourceLoader.load(WORDLIST_PATH)
    if resource == null:
        return null
    if not (resource is WordListResource):
        return null
    return resource
