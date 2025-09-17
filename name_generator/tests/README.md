# Tests

This directory now contains automated coverage for the name generator module. The suite focuses on the shared `GeneratorStrategy` contract and exercises happy-path name creation, validation failures, and deterministic RNG behaviour using a purpose-built mock implementation.

## Structure

- `test_generator_strategy.gd` – Table-driven checks that verify configuration validation helpers, enforce error metadata, and confirm deterministic sequences generated with identical RNG seeds.

## Running the suite

Use the project-wide runner script to execute every registered suite:

```bash
godot4 --headless --path . --script res://tests/run_all_tests.gd
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
