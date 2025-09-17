extends RefCounted

const GeneratorStrategyTests := preload("res://name_generator/tests/test_generator_strategy.gd")

func run() -> Dictionary:
    var test_instance := GeneratorStrategyTests.new()
    var result: Dictionary = test_instance.run()

    var total := int(result.get("total", 0))
    var passed := int(result.get("passed", 0))
    var failed := int(result.get("failed", 0))
    var failures := result.get("failures", [])
    if failures is Array:
        failures = failures.duplicate(true)
    else:
        failures = []

    var diagnostic := {
        "id": "legacy_test_generator_strategy",
        "name": "Legacy generator strategy test suite",
        "total": total,
        "passed": passed,
        "failed": failed,
        "failures": failures,
    }

    if result.has("suite"):
        diagnostic["suite"] = result["suite"]

    return diagnostic
