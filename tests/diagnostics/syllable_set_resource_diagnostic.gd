extends RefCounted

const SyllableSetResource := preload("res://name_generator/resources/SyllableSetResource.gd")
const TEMP_SAVE_PATH := "user://tmp_syllable_set_resource_diagnostic.tres"

var _checks: Array[Dictionary] = []

func run() -> Dictionary:
    _checks.clear()
    _cleanup_temp_resource()

    _record("assignments_emit_packed_arrays", func(): return _test_assignments_emit_packed_arrays())
    _record("allow_empty_middle_toggle", func(): return _test_allow_empty_middle_toggle())
    _record("serialization_round_trip", func(): return _test_serialization_round_trip())

    var failures: Array[Dictionary] = []
    for entry in _checks:
        if not entry.get("success", false):
            failures.append(entry)

    var result := {
        "id": "syllable_set_resource",
        "name": "SyllableSetResource data integrity diagnostic",
        "total": _checks.size(),
        "passed": _checks.size() - failures.size(),
        "failed": failures.size(),
        "failures": failures.duplicate(true),
    }

    _cleanup_temp_resource()

    return result

func _record(name: String, callable: Callable) -> void:
    var outcome := callable.call()
    var success := outcome == null
    _checks.append({
        "name": name,
        "success": success,
        "message": "" if success else String(outcome),
    })

func _test_assignments_emit_packed_arrays() -> Variant:
    var resource := SyllableSetResource.new()

    var expected_prefixes := PackedStringArray(["Ar", "Bel", "Cor"])
    var expected_middles := PackedStringArray(["in", "or"])
    var expected_suffixes := PackedStringArray(["dor", "ian"])

    resource.prefixes = PackedStringArray(expected_prefixes)
    resource.middles = PackedStringArray(expected_middles)
    resource.suffixes = PackedStringArray(expected_suffixes)

    if not (resource.prefixes is PackedStringArray):
        return "Prefixes should be stored as PackedStringArray."
    if not (resource.middles is PackedStringArray):
        return "Middles should be stored as PackedStringArray."
    if not (resource.suffixes is PackedStringArray):
        return "Suffixes should be stored as PackedStringArray."

    if resource.prefixes != expected_prefixes:
        return "Resource should retain prefixes in assigned order."
    if resource.middles != expected_middles:
        return "Resource should retain middle syllables in assigned order."
    if resource.suffixes != expected_suffixes:
        return "Resource should retain suffixes in assigned order."

    return null

func _test_allow_empty_middle_toggle() -> Variant:
    var resource := SyllableSetResource.new()

    if not resource.allow_empty_middle:
        return "allow_empty_middle should default to true."

    resource.allow_empty_middle = false
    if resource.allow_empty_middle:
        return "allow_empty_middle flag should update to false when disabled."

    resource.allow_empty_middle = true
    if not resource.allow_empty_middle:
        return "allow_empty_middle flag should update to true when re-enabled."

    return null

func _test_serialization_round_trip() -> Variant:
    var resource := SyllableSetResource.new()

    var expected_prefixes := PackedStringArray(["Ka", "Va"])
    var expected_middles := PackedStringArray(["len"])
    var expected_suffixes := PackedStringArray(["dor", "ian"])

    resource.prefixes = PackedStringArray(expected_prefixes)
    resource.middles = PackedStringArray(expected_middles)
    resource.suffixes = PackedStringArray(expected_suffixes)
    resource.allow_empty_middle = false
    resource.locale = "DiagnosticLocale"
    resource.domain = "DiagnosticDomain"

    if FileAccess.file_exists(TEMP_SAVE_PATH):
        var cleanup_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
        if cleanup_error != OK:
            return "Unable to remove pre-existing temp resource (%d)." % cleanup_error

    var save_error := ResourceSaver.save(resource, TEMP_SAVE_PATH)
    if save_error != OK:
        return "ResourceSaver failed with error code %d" % save_error

    if not ResourceLoader.exists(TEMP_SAVE_PATH):
        return "Saved resource not found at %s" % TEMP_SAVE_PATH

    var loaded := ResourceLoader.load(TEMP_SAVE_PATH)
    if loaded == null:
        return "ResourceLoader.load returned null for saved resource."
    if not (loaded is SyllableSetResource):
        return "Loaded resource should be a SyllableSetResource."

    var loaded_resource: SyllableSetResource = loaded

    if loaded_resource.prefixes != expected_prefixes:
        return "Serialized prefixes did not round-trip correctly."
    if loaded_resource.middles != expected_middles:
        return "Serialized middles did not round-trip correctly."
    if loaded_resource.suffixes != expected_suffixes:
        return "Serialized suffixes did not round-trip correctly."
    if loaded_resource.allow_empty_middle != false:
        return "Serialized allow_empty_middle flag should persist."
    if loaded_resource.locale != "DiagnosticLocale":
        return "Serialized locale value should persist."
    if loaded_resource.domain != "DiagnosticDomain":
        return "Serialized domain value should persist."

    return null

func _cleanup_temp_resource() -> void:
    if not FileAccess.file_exists(TEMP_SAVE_PATH):
        return

    var removal_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
    if removal_error != OK:
        push_warning("Failed to delete temp resource at %s (error %d)" % [TEMP_SAVE_PATH, removal_error])
