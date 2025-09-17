extends GeneratorStrategy
class_name SyllableChainStrategy

## Strategy that concatenates syllables from a [SyllableSetResource].
##
## The strategy draws deterministic syllable selections using the supplied
## [RandomNumberGenerator]. It validates the configuration dictionary before
## attempting to build a name and produces [GeneratorError] objects whenever the
## configuration or underlying resource cannot satisfy the request.
##
## Expected configuration keys:
## - ``syllable_set_path`` (*required*, ``String``): Resource path to a
##   ``SyllableSetResource``.
## - ``require_middle`` (*optional*, ``bool``): Force the generated name to
##   include at least one middle syllable.
## - ``middle_syllables`` (*optional*, ``Dictionary``): Range information that
##   controls how many middle syllables may appear. Supports the keys ``min``
##   and ``max``. When omitted, the strategy defaults to 0 or 1 middle syllable
##   depending on other configuration flags.
## - ``min_length`` (*optional*, ``int``): Minimum length for the final name. If
##   the generated name cannot reach this length the strategy reports an error.
## - ``post_processing_rules`` (*optional*, ``Array``): Sequence of dictionaries
##   describing regex replacements applied after syllables have been joined. The
##   dictionaries may provide ``pattern`` and ``replacement`` keys.
##
## Every selection honours the deterministic RNG supplied by the caller so
## external code can reproduce previously generated names by reusing the same
## seed.

const ArrayUtils := preload("res://name_generator/utils/ArrayUtils.gd")

func _get_expected_config_keys() -> Dictionary:
    return {
        "required": PackedStringArray(["syllable_set_path"]),
        "optional": {
            "require_middle": TYPE_BOOL,
            "middle_syllables": TYPE_DICTIONARY,
            "min_length": TYPE_INT,
            "post_processing_rules": TYPE_ARRAY,
        },
    }

func generate(config: Dictionary, rng: RandomNumberGenerator) -> Variant:
    var error := _validate_config(config)
    if error:
        return error

    var path_variant := config.get("syllable_set_path", "")
    if typeof(path_variant) != TYPE_STRING or String(path_variant).is_empty():
        return _make_error(
            "invalid_syllable_set_path",
            "Configuration must provide a non-empty 'syllable_set_path'.",
            {"syllable_set_path": path_variant},
        )

    var syllable_resource := ResourceLoader.load(path_variant)
    if syllable_resource == null:
        return _make_error(
            "missing_syllable_set",
            "Unable to load syllable set at '%s'." % path_variant,
            {"syllable_set_path": path_variant},
        )

    if not (syllable_resource is SyllableSetResource):
        return _make_error(
            "invalid_syllable_set_type",
            "Resource at '%s' is not a SyllableSetResource." % path_variant,
            {
                "syllable_set_path": path_variant,
                "received_type": syllable_resource.get_class(),
            },
        )

    var syllable_set: SyllableSetResource = syllable_resource
    error = _validate_syllable_set(syllable_set, config, path_variant)
    if error:
        return error

    var middle_range_variant := _parse_middle_range(config, syllable_set)
    if middle_range_variant is GeneratorError:
        return middle_range_variant

    var middle_range: Dictionary = middle_range_variant
    var middle_count := _pick_middle_count(middle_range, rng)

    var fragments: Array = []
    fragments.append(_pick_prefix(syllable_set, rng))

    for _i in range(middle_count):
        fragments.append(_pick_middle(syllable_set, rng))

    fragments.append(_pick_suffix(syllable_set, rng))

    var name := _join_with_smoothing(fragments)
    var min_length := max(config.get("min_length", 0), 0)

    var attempts := 0
    while name.length() < min_length and middle_count < middle_range["max"]:
        if syllable_set.middles.is_empty():
            break
        middle_count += 1
        fragments.insert(fragments.size() - 1, _pick_middle(syllable_set, rng))
        name = _join_with_smoothing(fragments)
        attempts += 1
        if attempts > 32:
            break

    if name.length() < min_length:
        return _make_error(
            "unable_to_satisfy_min_length",
            "Generated name did not reach the requested minimum length.",
            {
                "generated_name": name,
                "min_length": min_length,
                "middle_count": middle_count,
            },
        )

    var processed_name := _apply_post_processing(name, config.get("post_processing_rules", []))
    return processed_name

func _validate_syllable_set(
    syllable_set: SyllableSetResource,
    config: Dictionary,
    path_variant: String,
) -> GeneratorError:
    if syllable_set.prefixes.is_empty():
        return _make_error(
            "empty_prefixes",
            "Syllable set '%s' does not define any prefixes." % path_variant,
            {"syllable_set_path": path_variant},
        )

    if syllable_set.suffixes.is_empty():
        return _make_error(
            "empty_suffixes",
            "Syllable set '%s' does not define any suffixes." % path_variant,
            {"syllable_set_path": path_variant},
        )

    var require_middle := config.get("require_middle", false)
    if require_middle and syllable_set.middles.is_empty():
        return _make_error(
            "missing_required_middles",
            "Configuration requires middle syllables but the set is empty.",
            {"syllable_set_path": path_variant},
        )

    return null

func _parse_middle_range(
    config: Dictionary,
    syllable_set: SyllableSetResource,
) -> Variant:
    var require_middle := config.get("require_middle", false)
    var range_config := config.get("middle_syllables", null)

    var min_count := require_middle ? 1 : 0
    var max_count := require_middle ? max(1, min_count) : max(min_count, 1)

    if not syllable_set.middles.is_empty():
        max_count = max(max_count, syllable_set.middles.size())

    if range_config is Dictionary:
        if range_config.has("min"):
            min_count = int(range_config["min"])
        if range_config.has("max"):
            max_count = int(range_config["max"])
    elif range_config is Vector2i:
        min_count = range_config.x
        max_count = range_config.y
    elif range_config is Array and range_config.size() >= 2:
        min_count = int(range_config[0])
        max_count = int(range_config[1])
    elif range_config is PackedInt32Array and range_config.size() >= 2:
        min_count = range_config[0]
        max_count = range_config[1]
    elif range_config is int:
        min_count = int(range_config)
        max_count = int(range_config)

    if not syllable_set.allow_empty_middle and syllable_set.middles.size() > 0:
        min_count = max(min_count, 1)

    if min_count < 0:
        min_count = 0

    if max_count < min_count:
        return _make_error(
            "invalid_middle_range",
            "Configured 'middle_syllables' must satisfy min <= max.",
            {
                "min_count": min_count,
                "max_count": max_count,
            },
        )

    if syllable_set.middles.is_empty():
        if min_count > 0:
            return _make_error(
                "middle_syllables_not_available",
                "Middle syllables were requested but the resource does not define any.",
                {
                    "min_count": min_count,
                    "max_count": max_count,
                },
            )
        max_count = 0

    return {
        "min": min_count,
        "max": max(max_count, min_count),
    }

func _pick_middle_count(range: Dictionary, rng: RandomNumberGenerator) -> int:
    if range["min"] >= range["max"]:
        return range["min"]
    return rng.randi_range(range["min"], range["max"])

func _pick_prefix(syllable_set: SyllableSetResource, rng: RandomNumberGenerator) -> String:
    return _pick_from_packed_strings(syllable_set.prefixes, rng)

func _pick_middle(syllable_set: SyllableSetResource, rng: RandomNumberGenerator) -> String:
    return _pick_from_packed_strings(syllable_set.middles, rng)

func _pick_suffix(syllable_set: SyllableSetResource, rng: RandomNumberGenerator) -> String:
    return _pick_from_packed_strings(syllable_set.suffixes, rng)

func _pick_from_packed_strings(values: PackedStringArray, rng: RandomNumberGenerator) -> String:
    var as_array: Array = []
    for value in values:
        as_array.append(String(value))

    if as_array.is_empty():
        return ""

    return String(ArrayUtils.pick_uniform(as_array, rng))

func _join_with_smoothing(fragments: Array) -> String:
    var result := ""
    for fragment in fragments:
        var sanitized := String(fragment)
        if sanitized.is_empty():
            continue
        if result.is_empty():
            result = sanitized
        else:
            result = _smooth_boundary(result, sanitized)
    return result

func _smooth_boundary(left: String, right: String) -> String:
    if left.is_empty():
        return right
    if right.is_empty():
        return left

    var trimmed := _trim_duplicate_boundary(left, right)
    var base_left := trimmed[0]
    var base_right := trimmed[1]
    base_right = _smooth_vowel_overlap(base_left, base_right)
    base_right = _smooth_consonant_overlap(base_left, base_right)
    return base_left + base_right

func _trim_duplicate_boundary(left: String, right: String) -> Array:
    var left_last := left.substr(left.length() - 1, 1)
    var right_first := right.substr(0, 1)

    if left_last.is_empty() or right_first.is_empty():
        return [left, right]

    if left_last.to_lower() == right_first.to_lower():
        return [left, right.substr(1)]

    return [left, right]

func _smooth_vowel_overlap(left: String, right: String) -> String:
    if left.is_empty() or right.is_empty():
        return right

    var left_last := left.substr(left.length() - 1, 1).to_lower()
    var right_first := right.substr(0, 1).to_lower()

    if _is_vowel(left_last) and _is_vowel(right_first):
        return right.substr(1)

    return right

func _smooth_consonant_overlap(left: String, right: String) -> String:
    if left.is_empty() or right.is_empty():
        return right

    var left_last := left.substr(left.length() - 1, 1).to_lower()
    var right_first := right.substr(0, 1).to_lower()

    if _is_vowel(left_last) or _is_vowel(right_first):
        return right

    if right.length() == 1:
        return right

    var right_second := right.substr(1, 1).to_lower()
    if right_first == right_second:
        return right.substr(1)

    return right

func _is_vowel(character: String) -> bool:
    if character.is_empty():
        return false
    var vowels := "aeiou"
    return vowels.find(character[0]) != -1

func _apply_post_processing(name: String, rules: Array) -> String:
    if rules == null or rules.is_empty():
        return name

    var result := name
    for rule in rules:
        if not (rule is Dictionary):
            continue

        var pattern := String(rule.get("pattern", ""))
        if pattern.is_empty():
            continue

        var replacement := String(rule.get("replacement", ""))
        var regex := RegEx.new()
        var compile_status := regex.compile(pattern)
        if compile_status != OK:
            continue
        result = regex.sub(result, replacement)

    return result
