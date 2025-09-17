# Name Generator Module

This module mirrors the planned runtime architecture for the random name generator. The nested directories keep resources, processing strategies, utilities, development tools, and automated tests separated so engineers can evolve each concern independently.

- `resources/` – Static Godot resources, scriptable objects, and data packs distributed with the module.
- `strategies/` – Script logic implementing individual name-generation approaches.
- `utils/` – Shared helper scripts and low-level abstractions consumed across strategies.
- `tools/` – Editor and command-line helpers that assist with authoring or validating name data.
- `tests/` – Automated regression or integration tests that exercise the generator pipeline.

Place new scripts in the appropriate folder and update the Godot project settings when additional resource directories are required.

## Random Number Coordination

The `autoloads/RNGManager.gd` singleton exposes deterministic `RandomNumberGenerator`
streams keyed by a descriptive name. Request RNGs via
`RNGManager.get_rng("gameplay")` instead of creating ad-hoc instances so the
master seed can drive reproducible results across gameplay systems, tools, and
tests. Use `set_master_seed()` or `randomize_master_seed()` to control the global
seed, and persist/restore state with `save_state()` / `load_state()` when saving
or loading sessions.
