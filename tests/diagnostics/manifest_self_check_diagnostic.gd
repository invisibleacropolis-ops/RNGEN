extends RefCounted

## A minimal diagnostic to ensure the runner and manifest plumbing works.
func run() -> Dictionary:
    return {
        "name": "Manifest Self Check",
        "total": 1,
        "passed": 1,
        "failed": 0,
        "failures": []
    }
