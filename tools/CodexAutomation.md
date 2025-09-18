# Codex Automation Process Manager

The `tools/codex_godot_process_manager.py` module provides the Python-facing
wrapper that Codex uses to launch and supervise headless Godot sessions.  It
is designed to follow the communication and orchestration guidelines described
in the "Python Godot Automation Design Bible" so that outside engineers can
easily integrate Codex-driven automation into their own tooling.

## Environment variables

Two environment variables define the default launch configuration:

- `CODEX_GODOT_BIN`: Absolute path to the Godot 4 executable to run.  The
  module will refuse to start if this is not provided either via the
  environment or the class constructor.
- `CODEX_PROJECT_ROOT`: Path to the Godot project that should be mounted via
  `--path`.  This directory must contain the canonical `project.godot` file.

Both variables can be overridden by passing explicit values to the
`CodexGodotProcessManager` constructor.  Manual operators often provide custom
arguments or environment tweaks while Codex production runs typically rely on
CI provided defaults.

## Session lifecycle

```python
from tools.codex_godot_process_manager import CodexGodotProcessManager

with CodexGodotProcessManager(extra_args=["-s", "res://tests/run_all_tests.gd"]) as manager:
    # Send JSON-RPC commands and iterate over responses.
    request_id = manager.send_command("scenario.load", {"name": "Arena"})
    for message in manager.iter_messages(timeout=1.0):
        print(message)
```

- `start()` launches `godot --headless --path <project>` with the configured
  arguments and immediately sends an automatic `codex.banner` negotiation
  request.  The response is captured and surfaced via
  `manager.describe_session().banner`.
- `stop()` gracefully terminates the process and joins the reader threads.  A
  context manager (`with` block) is provided for convenience.

## Communication model

- Commands are serialized as JSON-RPC style dictionaries with a monotonically
  increasing `id`, a `method` string, and a `params` dictionary.  Each command
  is written as a single newline-delimited JSON document on stdin.
- Responses are consumed through `iter_messages()`, which parses each newline
  from stdout and yields decoded dictionaries.  The banner response is
  consumed internally so user code only sees domain-specific payloads.
- Any stdout line that fails JSON parsing or every stderr line is converted
  into a structured diagnostic record.  These records can be inspected via
  `iter_stderr_diagnostics()` and include timestamps, severity levels, and the
  originating stream.

## Heartbeat and timeout handling

Codex runs are often unattended, so the manager includes a lightweight
heartbeat monitor.  When `heartbeat_interval` is provided the manager wakes up
periodically to check when the last stdout message was seen.  If the elapsed
silence exceeds `heartbeat_timeout` (defaults to the interval) a warning
record with `stream="heartbeat"` is injected into the diagnostics queue.
This allows Codex to detect hung scenarios without preventing manual
operators from running longer experiments (set the interval to `None` to
disable the watchdog).

## Introspection

`describe_session()` returns a `SessionDescription` dataclass containing the
active command line, process ID, negotiated banner, and heartbeat settings.
This makes it straightforward to mirror Codex' perspective on a live session
when debugging in external tooling or when collecting telemetry for CI.


## EventBus replay troubleshooting

Codex replays EventBus transcripts by launching the headless runner at
`res://tests/eventbus_replay_runner.gd`.  The script instantiates the harness
scene, validates the JSON transcript, and calls
`EventBusHarness.replay_signals_from_json()` so every entry is exercised against
the live EventBus contracts.  Outcomes are streamed as newline-delimited JSON
records that Codex aggregates into a report.  Manual engineers can mirror the
same workflow by running:

```bash
godot4 --headless --path <project> --script res://tests/eventbus_replay_runner.gd <path/to/replay.json>
```

The transcript must be a JSON array of dictionaries.  Each entry requires a
`signal_name` string and a `payload` dictionary; additional metadata keys are
ignored.  Any structural issue (missing keys, non-dictionary payloads, malformed
JSON) triggers a fast-fail diagnostic before Godot emits the replay, preventing
partial runs from masking schema drift.

For automation, `tools/codex_replay_eventbus.py` wraps the process manager so
Codex can collect structured results.  The helper accepts the replay path plus
optional `--export-log` and `--echo-log` flags to persist or mirror the harness
log.  It parses every `eventbus_replay_*` JSON line into a machine-readable
report that downstream systems or engineers can inspect without scraping human
text.  The module also exposes a `format_report()` utility to render the results
in a human-friendly summary when troubleshooting locally.

When diagnosing failures, enable the echo flag to capture the harness transcript
alongside Codex' summary, or export the log to disk for attachment to bug
reports.  Because the runner reuses the same harness logic that powers the
in-editor tooling, reproducing Codex' steps manually ensures parity between CI
and local debugging.

## Running the manifest suite end-to-end

The `tools/codex_run_manifest_tests.py` helper provides a batteries-included
command line for executing the entire manifest suite in the same way Codex does
during automated reviews.  Outside engineers can use it to reproduce failures
locally, capture diagnostics, or experiment with new test manifests.

## Preflight orchestration with Codex

Codex now exposes a single entry point for end-to-end validation via
`tools/codex_preflight.py`.  The helper mirrors the automation workflow used in
production by layering lightweight parse checks in front of the manifest suite
so obvious syntax issues are caught before Godot boots.

### Step-by-step workflow

1. Select the directories or individual `.gd` files you want to validate.  When
   no paths are provided the script defaults to scanning the current working
   directory.
2. Run the preflight helper.  By default it emits Codex-friendly JSON so the
   orchestrator can consume telemetry and diagnostics directly:

   ```bash
   python tools/codex_preflight.py src tests
   ```

3. When the parse phase finds no issues the tool automatically chains into
   `codex_run_manifest_tests.py`.  Additional flags can be forwarded using the
   `--manifest-args <args>` pattern:

   ```bash
   python tools/codex_preflight.py --manifest-args --project-root $CODEX_PROJECT_ROOT
   ```

4. Use `--human` if you prefer a concise textual summary instead of JSON while
   iterating locally.  The flag preserves the same control flow but formats the
   report for terminal consumption.

5. Combine `--skip-parse` or `--skip-manifest` to focus on a single phase.  For
   example, `python tools/codex_preflight.py --skip-parse --manifest-args \
   --manifest tests/custom_manifest.json` runs only the manifest suite while
   still surfacing aggregated telemetry.

The JSON payload always reports how many scripts were scanned, the number of
parse failures, whether the manifest suite ran, and the resulting coverage
statistics (scripts passed/failed).  Codex uses these counts to short-circuit
automation when syntax regressions are detected, while outside engineers can
embed the same helper in CI pipelines to mirror the production guard rails.

### Step-by-step workflow

1. Export the standard Codex environment variables so the script can discover
   your Godot installation and project root:

   ```bash
   export CODEX_GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
   export CODEX_PROJECT_ROOT=/path/to/Glevel3
   ```

2. (Optional) Inspect `tests/tests_manifest.json` to understand which scenes or
   scripts will be executed.  The manifest is the same file consumed in Codex
   runs.

3. Invoke the runner.  By default it cleans stale `tests/results.*` artifacts,
   launches Godot headlessly, and emits both a human friendly summary and a
   JSON payload that Codex can stream back to the operator:

   ```bash
   python tools/codex_run_manifest_tests.py
   ```

4. When you need persistent evidence for a review, add `--output snapshots/` to
   capture `summary.txt` and `codex_payload.json` artifacts.  These files mirror
   what Codex archives during CI validation.

5. Use `--max-retries 3 --retry-delay 2` if you suspect flaky tests.  Each retry
   clears the report files before relaunching Godot so the resulting payloads
   accurately represent the final attempt.

6. Inspect `tests/results.json` and `tests/results.xml` after the run for the
   detailed assertion counts and per-script diagnostics that power the summary.
   The JSON structure is parsed into a rich payload that the runner prints to
   stderr for Codex to consume.

### Example Codex prompts

Codex operators usually seed the assistant with one of the following prompts to
drive the manifest suite:

- _"Use `tools/codex_run_manifest_tests.py --output artifacts/ci` to gather a
  structured manifest report and share the summary with me."_
- _"Re-run the manifest tests with two retries and include any failing script
  diagnostics in the Codex JSON payload."_
- _"Clean the stale test reports, execute the manifest suite, and attach the
  resulting `codex_payload.json` so I can inspect the raw numbers."_

Because the CLI is deterministic and mirrors the automation harness, any prompt
that works in Codex will behave identically for local engineers.

