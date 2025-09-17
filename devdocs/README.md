# Developer Documentation

This folder centralises implementation references for engineers working on the random name generator. Start here to understand how to extend the strategy catalogue, wire new datasets into the project, and invoke the command-line tooling.

- [`strategies.md`](strategies.md) – Configuration keys, validation behaviour, and a step-by-step recipe for implementing new strategies.
- [`tooling.md`](tooling.md) – Usage notes for the command-line scripts that support data authoring and QA.
- [`sentences.md`](sentences.md) – Pattern library for Template and Hybrid sentence builders, including seeding guidance and dataset-driven examples.

After updating configurations, run the regression suite to confirm deterministic guarantees remain intact:

```bash
godot --headless --script res://tests/run_all_tests.gd
```
