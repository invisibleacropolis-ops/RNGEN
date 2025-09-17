# Strategy Authoring Guide

Strategies inherit from [`GeneratorStrategy`](../name_generator/strategies/GeneratorStrategy.gd), a `RefCounted` base class that standardises configuration validation and error reporting. Each subclass must provide a `generate(config, rng)` implementation that uses the supplied `RandomNumberGenerator` to produce deterministic results.

## Configuration keys

`GeneratorStrategy` exposes `_get_expected_config_keys()` so subclasses can document their contract. The method must return a dictionary with the following shape:

| Key        | Type                          | Purpose |
|------------|-------------------------------|---------|
| `required` | `PackedStringArray` or `Array` | Lists configuration keys that must be present. Missing keys trigger a `GeneratorError` with code `"missing_required_keys"`. |
| `optional` | `Dictionary`                  | Maps optional keys to expected variant types (e.g. `TYPE_STRING`, `TYPE_INT`). Values with mismatched types trigger `"invalid_key_type"` errors. |

To run the validation pipeline, call `_validate_config(config)` from the start of your `generate()` override. The helper checks:

1. The caller supplied a dictionary (otherwise `"invalid_config_type"` is returned).
2. All required keys exist.
3. Optional keys match the declared types.

Handle the returned `GeneratorError` by either throwing a descriptive exception, logging the issue, or propagating the error back to the caller.

## Implementing a new strategy

1. Create a new script in `name_generator/strategies/` that `extends GeneratorStrategy`.
2. Override `_get_expected_config_keys()` to document the keys you need. Keep the list minimal so configuration remains ergonomic.
3. Implement `generate(config, rng)`:
   - Call `_validate_config(config)` and return early if it produces an error.
   - Cast `config` to a `Dictionary` and pull out the values you declared in `_get_expected_config_keys()`.
   - Use helpers such as [`ArrayUtils.pick_random_deterministic`](../name_generator/utils/ArrayUtils.gd) to make seeded selections without touching global RNG state.
   - Assemble the final string or data structure that represents the generated name.
4. Add smoke tests under `name_generator/tests/` that exercise the new strategy. Use the provided [`smoke_test.gd`](../name_generator/tests/smoke_test.gd) runner as a template and call `quit()` when the script finishes.
5. Update documentation or sample configurations where appropriate so downstream engineers can discover the new strategy.

## Error handling tips

- Use `_make_error(code, message, details)` to produce consistent error payloads when you detect domain-specific issues (e.g. malformed Markov chains).
- When normalising user-supplied arrays, reuse functions in `ArrayUtils` to keep assertions and deterministic behaviour consistent.
- If your strategy consumes external data, log descriptive `details` in the error payload (such as the dataset path or offending entry) so tooling scripts can surface the information to authors.
