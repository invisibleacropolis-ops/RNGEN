extends RefCounted

const HybridStrategy := preload("res://name_generator/strategies/HybridStrategy.gd")
const GeneratorStrategy := preload("res://name_generator/strategies/GeneratorStrategy.gd")

const WORDLIST_PATH := "res://tests/test_assets/wordlist_basic.tres"
const SYLLABLE_PATH := "res://tests/test_assets/syllable_basic.tres"
const MARKOV_PATH := "res://tests/test_assets/markov_basic.tres"
const MISSING_NAME_GENERATOR_PATH := "res://tests/test_assets/missing_name_generator.gd"

class MissingNameGeneratorHybridStrategy:
    extends HybridStrategy

    func _get_name_generator_script_path() -> String:
        return MISSING_NAME_GENERATOR_PATH

    func _resolve_name_generator_singleton() -> Object:
        return null

    func _has_engine_singleton(_name: StringName) -> bool:
        return false

    func _get_engine_singleton(_name: StringName) -> Object:
        return null

var _total := 0
var _passed := 0
var _failed := 0
var _failures: Array[Dictionary] = []

func run() -> Dictionary:
    _total = 0
    _passed = 0
    _failed = 0
    _failures.clear()

    _run_test("hybrid_generates_expected_structure", func(): _test_hybrid_structure())
    _run_test("hybrid_generation_is_deterministic", func(): _test_determinism())
    _run_test("missing_name_generator_resource_surfaces_error", func(): _test_missing_name_generator_resource())

    return {
        "suite": "HybridStrategy",
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

func _test_hybrid_structure() -> Variant:
    var strategy := HybridStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 12345

    var config := _make_config()
    var result := strategy.generate(config, rng)

    if result is GeneratorStrategy.GeneratorError:
        return "HybridStrategy returned error: %s" % result.message

    var text := String(result)
    if text.find("$") != -1:
        return "Template placeholders must be replaced in the final output."

    var parts := text.split(" ", false)
    if parts.size() < 2:
        return "Hybrid output should contain a space between title and name."

    var title := parts[0]
    var body := parts[1]

    var allowed_titles := ["Brave", "Mighty", "Shadow"]
    if not allowed_titles.has(title):
        return "Title component must originate from the word list resource."

    if body.length() < 3:
        return "Generated body component must contain at least three characters."

    return null

func _test_determinism() -> Variant:
    var strategy := HybridStrategy.new()
    var first_rng := RandomNumberGenerator.new()
    first_rng.seed = 2024
    var second_rng := RandomNumberGenerator.new()
    second_rng.seed = 2024

    var config_one := _make_config()
    var config_two := _make_config()

    var first := strategy.generate(config_one, first_rng)
    var second := strategy.generate(config_two, second_rng)

    if first is GeneratorStrategy.GeneratorError:
        return "First generation failed: %s" % first.message
    if second is GeneratorStrategy.GeneratorError:
        return "Second generation failed: %s" % second.message

    if String(first) != String(second):
        return "Hybrid generation must be deterministic for identical seeds."

    var alternate_rng := RandomNumberGenerator.new()
    alternate_rng.seed = 99
    var alternate := strategy.generate(_make_config(), alternate_rng)
    if alternate is GeneratorStrategy.GeneratorError:
        return "Alternate generation failed: %s" % alternate.message

    if String(alternate) == String(first):
        return "Different seeds should yield different hybrid names."

    return null

func _test_missing_name_generator_resource() -> Variant:
    var strategy := MissingNameGeneratorHybridStrategy.new()
    var rng := RandomNumberGenerator.new()
    rng.seed = 321

    var config := {
        "steps": [
            {
                "strategy": "wordlist",
                "wordlist_paths": [WORDLIST_PATH],
            },
        ],
    }

    var result := strategy.generate(config, rng)

    if not (result is GeneratorStrategy.GeneratorError):
        return "Expected missing NameGenerator script to return a GeneratorError."

    var error := result as GeneratorStrategy.GeneratorError
    if error.code != "missing_resource":
        return "Missing NameGenerator script should report missing_resource, received %s" % error.code

    if not String(error.message).begins_with("Missing resource"):
        return "Missing NameGenerator script error should use the standard prefix."

    if String(error.details.get("path", "")) != MISSING_NAME_GENERATOR_PATH:
        return "Missing NameGenerator script error should surface the failing path."

    return null

func _make_config() -> Dictionary:
    return {
        "seed": "hybrid_test_seed",
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
                "require_middle": false,
                "store_as": "suffix",
            },
        ],
        "template": "$title $root$suffix",
    }
