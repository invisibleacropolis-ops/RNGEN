# Tests

Automated checks live in this directory. Start with the `smoke_test.gd` script, which validates the deterministic helpers in [`ArrayUtils.gd`](../utils/ArrayUtils.gd) and demonstrates how to write headless runners that quit when finished.

Run the suite from the project root:

```bash
godot --headless --path . --script res://name_generator/tests/smoke_test.gd
```

Add additional scripts here as you implement strategies or utilities. Prefer small, deterministic checks so they can run quickly in CI.
