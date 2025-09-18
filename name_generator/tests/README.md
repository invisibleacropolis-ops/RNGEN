# Tests


Automated checks live in this directory. Start with the `smoke_test.gd` script, which validates the deterministic helpers in [`ArrayUtils.gd`](../utils/ArrayUtils.gd) and demonstrates how to write headless runners that quit when finished.

Run the suite from the project root:

```bash
godot --headless --path . --script res://name_generator/tests/smoke_test.gd
```

Add additional scripts here as you implement strategies or utilities. Prefer small, deterministic checks so they can run quickly in CI.

This directory now contains automated coverage for the name generator module. The suite focuses on the shared `GeneratorStrategy` contract and exercises happy-path name creation, validation failures, and deterministic RNG behaviour using a purpose-built mock implementation.

## Structure

- `test_generator_strategy.gd` – Table-driven checks that verify configuration validation helpers, enforce error metadata, and confirm deterministic sequences generated with identical RNG seeds.

## Running the suite

Use the project-wide group runner to execute every registered suite:

```bash
godot --headless --path . --script res://tests/run_generator_tests.gd
```

### Expected output

When all tests succeed you should see console logs similar to:

```
Running suite: Generator Strategy Suite
  Total: 5
  Passed: 5
  Failed: 0
  ✅ All tests passed in suite: Generator Strategy Suite

Test summary: 5 passed, 0 failed, 5 total.
ALL TESTS PASSED
```

Any failures are reported with the test name and human-readable diagnostics to simplify debugging for engineers integrating new strategies.

