# Platform GUI Checklists

These printable checklists summarise the most common Platform GUI workflows. Duplicate them into project wikis, sprint handoffs, or build scripts so every export stays deterministic.

## Launch readiness

- [ ] Repository synced and submodules (if any) initialised.
- [ ] Godot 4.4 installed and pointing to the repository root.
- [ ] `project.godot` opened from the root (no renamed folder).
- [ ] Autoloads `RNGManager`, `NameGenerator`, and `RNGProcessor` enabled.
- [ ] DebugRNG toolbar visible (toggle from **View > Docks** if hidden).
- [ ] Optional: DebugRNG metadata filled out (session label, ticket ID, notes).
- [ ] Active workspace preset selected in **Admin Tools** if you rely on custom layouts.

## Batch export readiness

- [ ] Generators tab configured with the desired strategy and validated inputs.
- [ ] Seeds tab shows the expected master seed (apply manual seed if needed).
- [ ] **Randomize seed before each run** disabled unless a unique set is required.
- [ ] DebugRNG recording enabled for telemetry-rich export bundles.
- [ ] Jobs staged in the Exports tab with meaningful annotations (locale, sprint, feature tag).
- [ ] Export format selected (CSV or JSON) and verified against downstream consumer expectations.
- [ ] **Include DebugRNG snapshot** toggle enabled if QA needs timeline context.
- [ ] Destination directory writable (check OS permissions when exporting to shared drives).

## Post-export handoff

- [ ] Bundle folder renamed with ticket ID and date stamp.
- [ ] Manifest and payload files spot-checked for expected data volume.
- [ ] `rng_state.json` imported locally to verify reproducibility.
- [ ] DebugRNG TXT reviewed for warnings before delivery.
- [ ] Summary README updated with platform, localisation, and sprint notes.
- [ ] Bundle archived in the studio’s handoff location and linked from the tracking ticket.

## Debug session wrap-up

- [ ] Debug Logs filtered for errors and warnings tied to the current investigation.
- [ ] Exported log attached to the ticket or stored in the incident archive.
- [ ] Seeds tab state exported and committed to the repo (or added to the ticket) for future replay.
- [ ] Admin Tools presets synced if new bookmarks or layouts should become the team default.
- [ ] Handbook and checklists updated when workflows change.

Keep these checklists version-controlled. Whenever the GUI gains a new tab or workflow, update this file alongside [`devdocs/platform_gui_handbook.md`](./platform_gui_handbook.md).
