# Name Generator Module

This module mirrors the planned runtime architecture for the random name generator. The nested directories keep resources, processing strategies, utilities, development tools, and automated tests separated so engineers can evolve each concern independently.

- `resources/` – Static Godot resources, scriptable objects, and data packs distributed with the module.
- `strategies/` – Script logic implementing individual name-generation approaches.
- `utils/` – Shared helper scripts and low-level abstractions consumed across strategies.
- `tools/` – Editor and command-line helpers that assist with authoring or validating name data.
- `tests/` – Automated regression or integration tests that exercise the generator pipeline.

Place new scripts in the appropriate folder and update the Godot project settings when additional resource directories are required.
