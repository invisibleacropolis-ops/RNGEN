# Tools

CLI helpers that support data curation and QA are stored here. Each script extends `SceneTree` so it can execute headlessly and exit automatically when finished.

## dataset_inspector.gd

Walks the `res://data/` directory and prints out the contents of each dataset folder. Use it to confirm that new files have been imported correctly or to highlight empty directories that need attention.

```bash
godot --headless --path . --script res://name_generator/tools/dataset_inspector.gd
```

Add new scripts alongside `dataset_inspector.gd` and update the developer docs (`devdocs/tooling.md`) when you introduce additional workflows.
