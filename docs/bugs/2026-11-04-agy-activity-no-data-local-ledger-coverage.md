# Bug: Agent Activity agy panels show No data without identifying missing telemetry source

**Filed:** 2026-11-04
**Branch:** `k3d-manager-v1.43.14`
**Status:** LANDED `b44f5efd`, independent verify PASS 2026-11-06 (24 tests on the landed commit; 21 red on the parent, including M1 to M4; 14 mutants red). The verifier read the exporter's agy section for label shapes before writing its tests, which its brief ruled out; it did not read this spec's Fix or the diff. `scripts/tests/bin/machine_setup_acceptance.bats` landed outside `## Files` by allowed exception. Live E3, Claude half PASS on `m4-air` 2026-11-06: session and token totals equal an independent transcript read in 1d, 7d and 30d, source `transcripts`, 0 skipped lines, and the 1 dispatched session in 30d is tracked (89 of 90 untracked). The operator's Grafana check is open. The Fix section below replaces "Proposed fix / acceptance"
**Approval:** operator, 2026-11-06: "go with your suggestion". The exporter and dashboard change only; it starts no hub workload change beyond the ArgoCD-synced dashboard.
**Priority:** P2 — loss of AI activity observability across machine migration / worker execution
**Severity:** Moderate — missing telemetry and misleading visibility, not evidence that agy itself stopped working
**Component:** `bin/k3dm-agy`, `bin/k3dm-dispatch-metrics`, `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`, machine-setup / hub cutover, `docs/guides/grafana-dashboards/k3dm-agent-activity.md`
**Related:** `docs/plans/v1.43.6-dispatch-codex-solo-activity.md`, `docs/bugs/2026-10-24-agy-wrapper-install-overwrites-real-agy-binary.md` (different, fixed installer hazard)

## Symptom and evidence

Operator screenshot on 2026-11-04 shows the **All agy activity (including outside the dispatcher)** row with `No data` in all six panels: agy sessions, Untracked agy sessions, agy active hours, agy sessions by mode, agy untracked by repo, and agy tokens. The operator has used agy recently, so a complete telemetry blank warrants investigation. Other dashboard panels, exporter logs, Pushgateway data, and actual wrapper location were not captured in the screenshot. Do not claim that the collector has been live-diagnosed.

Static inspection on `k3d-manager-v1.43.14`:

1. `bin/k3dm-agy` writes session records only for invocations passing through the wrapper to `${K3DM_AGENT_LEDGER_DIR:-$HOME/.local/share/k3d-manager/agent-sessions}/agy.jsonl`. Direct invocation of the real `agy` binary is not covered; interactive sessions are written when they exit. Helper subcommands such as `agy models` are intentionally excluded.
2. `bin/k3dm-dispatch-metrics` calls `_agy_metrics` on the **local machine's** ledger path. On read error (including missing file), `_agy_metrics` silently returns without producing `k3dm_agy_sessions`, `k3dm_agy_active_seconds` or a source-presence/age metric. If the ledger has no sessions in the dashboard's 1d/7d/30d windows, the exporter likewise emits no series for that window. Token metrics are further conditional on parseable `usage`; interactive sessions normally do not have usage.
3. The exporter pushes to `http://localhost:19094/metrics/job/k3dm-dispatch` by default; Grafana reads `k3dm_agy_*` from Prometheus. An exporter running on M5 cannot directly see unreplicated records written on M2 or an older M4. This is an architectural possibility, not yet a confirmed diagnosis.
4. The wrapper installer deliberately uses `~/.local/share/k3d-manager/bin` as a safe default; its directory must precede the real `agy` on `PATH`. The former Oct 24 P1 installer-overwrite bug was fixed and is not the cause demonstrated by this screenshot.

## Hypotheses to discriminate in live diagnosis

- H1: `agy` resolves to the real binary rather than the dedicated wrapper; recent invocations never entered the ledger.
- H2: `agy.jsonl` exists with sessions on another Mac (e.g. M2/M4), but the M5 Pushgateway exporter scans only M5's ledger.
- H3: The wrapper records correctly on M5 but the dispatch metrics scheduled job or Pushgateway export is stale/failing.
- H4: Ledger is empty, malformed, unreadable, or contains only records outside the selected `$window`; the exporter fails silently or produces no series.
- H5: Grafana is looking at stale/different datasource, metric labels, or time range. Check only after source/export evidence.

## Read-only live diagnostic procedure

On the Mac where agy is launched, and separately on the Mac where `k3dm-dispatch-metrics` runs:

```bash
type -a agy
ls -l ~/.local/share/k3d-manager/bin/agy ~/.local/bin/agy 2>/dev/null
ls -l ~/.local/share/k3d-manager/agent-sessions/agy.jsonl 2>/dev/null
wc -l ~/.local/share/k3d-manager/agent-sessions/agy.jsonl 2>/dev/null
bin/k3dm-dispatch-metrics --dry-run | grep '^k3dm_agy_' | head -30
```

Do **not** paste raw ledger contents, as they may contain local activity identifiers. Compare aggregate counts and timestamps only. Check the time selector `$window` (1d, 7d, 30d), exporter scheduling, and Pushgateway `job=k3dm-dispatch` freshness. Query Prometheus for `k3dm_agy_sessions` and `k3dm_dispatch_ledger_timestamp_seconds` separately. No synthetic sessions, misleading zeros or fake token estimates.

## Proposed fix / acceptance

- [ ] Identify and reproduce the actual loss point on the active host(s): wrapper interception, local ledger, scheduled exporter, Pushgateway or Grafana. Record sanitized evidence before implementing.
- [ ] Add bounded `k3dm_agy_source_present`, source-read-error/valid-row coverage, latest-observed-session timestamp and exporter-heartbeat metrics. Expose an explicit **source unavailable / no recent wrapped sessions / metrics stale** distinction. Absence is not zero usage.
- [ ] Add a machine-setup and post-cutover check for the wrapper's `PATH` precedence, existence/readability of the ledger, and exporter installation, without overwriting the real agy CLI. Make the health status visible in machine-setup readiness output.
- [ ] Establish an intentional multi-Mac activity aggregation policy: identify the source host for each record, prevent double-counting and preserve privacy; never silently report M5-only results as all activity across M2/M4/M5. Do not copy `~/.gemini/antigravity` conversations or credentials.
- [ ] Keep token reporting conditional on parseable usage; explain interactive mode's expected token blind spot in Grafana without blanking session counts.
- [ ] Add offline regression tests for missing/empty/malformed ledger, no in-window records, wrapper bypass, recorded interactive run and print-mode usage; verify missing data is not emitted as a false zero. Add a live test with one approved, non-sensitive wrapped session, source freshness and matching Prometheus/Grafana values.
- [ ] Avoid PR and avoid direct writes to `main`; fix on the active release branch after root cause is verified.

## Definition of done

1. Operator can distinguish no usage from ingestion failure and wrong-host collection.
2. Recent eligible wrapped agy runs appear under the correct 1d/7d/30d window, with explicit coverage limitations.
3. Metrics exporter health still reports correctly when `agy.jsonl` is missing; no fabricated usage values.
4. M5 post-migration validation protects against recurrence.


## M4 live evidence — 2026-11-04, 06:09 PST

The operator ran `type -a agy` on M4. Shell resolution showed an `agy` executable under `~/.local/bin/agy` first, and `/opt/homebrew/bin/agy` second; the dedicated wrapper default path `~/.local/share/k3d-manager/bin/agy` was **not** listed. This suggests the safe wrapper is not installed/on PATH, but `type -a` alone does **not** prove whether either visible executable is itself a symlink to `bin/k3dm-agy`; resolve/readlink before concluding bypass.

On the same M4 checkout, `bin/k3dm-dispatch-metrics --dry-run | grep '^k3dm_agy_' | head -30` produced zero matching lines. This independently demonstrates **no agy metrics emitted by that M4 local dry-run**; it does not establish whether M4 is the production Pushgateway exporter or whether M5 has ledger records.

Next minimal, read-only discriminators:

```bash
ls -l ~/.local/bin/agy /opt/homebrew/bin/agy ~/.local/share/k3d-manager/bin/agy 2>/dev/null
ls -l ~/.local/share/k3d-manager/agent-sessions/agy.jsonl 2>/dev/null
wc -l ~/.local/share/k3d-manager/agent-sessions/agy.jsonl 2>/dev/null
```

Repeat `type -a agy`, ledger count, and `bin/k3dm-dispatch-metrics --dry-run | grep '^k3dm_agy_'` **on M5**, and determine which machine actually publishes `k3dm-dispatch` metrics. Avoid running `agy` merely to synthesize metrics; do not expose raw session ledger or authentication data. Do not run the wrapper installer until the real binary path is confirmed: the historical installer collision is documented separately.


## Operator follow-up — 2026-11-04, 06:10 PST

Operator reports **"m5 has nothing"** in response to requested M5 Agy telemetry checks. Treat this as reported absence of Agy telemetry on M5; precise file existence, wrapper PATH and exporter heartbeat on M5 are not independently captured yet. Do not infer zero actual Agy usage from this observation.

Combined evidence: M4 `type -a agy` does not list the dedicated wrapper path and its exporter dry-run emitted no `k3dm_agy_*` series; M5 reportedly has no Agy data; Grafana shows all six Agy panels as `No data`. Prioritize tracing the host running the scheduled metrics exporter, then safely enabling wrapper collection on each active worker host and defining host-tagged multi-host aggregation. Avoid pretending that installing a wrapper on M5 alone recovers M4 activity or retroactively reconstructs historical sessions. Preserve existing real `agy` binaries.

**Remaining evidence for exact root cause:** `ls -l` or `readlink` of M4 executable paths; source ledger presence/count on M4/M5; scheduled metrics exporter location and output on M5; Prometheus target freshness. No production modifications or synthetic telemetry are authorized by this note.

## Recurrence and root cause — Argon's 5-hour lead session left no metrics (2026-11-05, Claude, M4)

The operator reported that Gemini Argon's run on the keychain-stall bug (2026-11-03, about 5 h of active work) shows nothing on Agent Activity. Read-only findings on `m4-air.local`:

1. **The wrapper is not installed on the M4.**
   - `type -a agy` resolves `~/.local/bin/agy`, then `/opt/homebrew/bin/agy`. Both are Mach-O binaries of about 200 MB (the real CLI). `~/.local/bin/agy` is dated 2026-11-04 06:18 and `/opt/homebrew/bin/agy` 2026-11-05 04:31, so agy's own updater writes both paths.
   - The `make` wrapper install (`Makefile:498-502`) needs `$(AGY_WRAPPER_DIR)/agy` to be a symlink to `bin/k3dm-agy`, and refuses to replace a real binary.
   - `~/.local/share/k3d-manager/agent-sessions/agy.jsonl` does not exist, so `bin/k3dm-agy` has never recorded a run on this machine.
2. **Argon worked as the lead (coordinator), not as a dispatched worker.**
   - The dispatch ledger records it only as `coordinator_identity` on the six Luna dispatches it started (11-03 17:19–19:59 PST).
   - Its own turns, tokens and time sit outside every collector.
3. **agy already records everything we need, locally.**
   - Each session writes `~/.gemini/antigravity-cli/brain/<session>/.system_generated/logs/transcript_full.jsonl`, with `created_at`, `type`, `status` and `tool_calls` on every step, plus `input_tokens`, `cache_read_tokens` and `output_tokens` on model steps. 493 sessions have one.
   - The Argon session `59d11804-5224-4816-a1d8-d1360fecbf99`: 1,439 steps from 2026-11-04T00:35:05Z to 2026-11-05T13:20:19Z. Its token fields sum to input 3,488,941, cache read 86,963,859 and output 322,136.

**Fix direction (changes the Fix of this bug):**
- Read the agy transcripts directly, the same way the Claude collector reads `~/.claude/projects/*.jsonl`, instead of relying on the wrapper ledger. This survives agy self-updates and covers interactive lead sessions.
- Keep the wrapper only for dispatch linkage.
- Treat the absent wrapper as a `machine-check` warning, not as the data source.
- Stub fixtures copy step shapes from a real `transcript_full.jsonl` (host, date and session id in a comment). Never copy message content: it can hold repo text and secrets.

## Read-only check, 2026-11-06 (Claude, `m4-air` and `m5-air`)

- `m4-air`: 493 transcripts, newest about 16 h old. `m5-air`: 30 transcripts, newest about 6 h old. Neither host has `agent-sessions/agy.jsonl`.
- Step keys seen in the newest 40 transcripts on both hosts: `step_index`, `source`, `type`, `status`, `created_at`, `content`, `input_tokens`, `cache_read_tokens`, `output_tokens`, `thinking`, `tool_calls`, `error`. Types: `USER_INPUT`, `PLANNER_RESPONSE`, `GENERIC`, `SYSTEM_MESSAGE`, `CHECKPOINT`. Statuses: `DONE`, `ERROR`, `RUNNING`. `created_at` looks like `2026-11-06T02:45:59Z`; token fields are integers and appear only on `PLANNER_RESPONSE`. Neither a working directory nor a mode is present.
- The exporter runs from dispatch events and pushes one shared `k3dm-dispatch` group, so today it reports the M4. No launchd agent runs it on either host.

## Fix

Scope: the host running the exporter. Combining hosts is out of scope and needs its own decision, so the panel states which host it reports.

1. Add a transcript collector to `bin/k3dm-dispatch-metrics`. It reads `~/.gemini/antigravity-cli/brain/*/.system_generated/logs/transcript_full.jsonl`, skipping files not modified inside the longest window. `K3DM_AGY_BRAIN_DIR` overrides the root. The session id is the directory name.
2. It reads only `created_at` and the three token fields. It must never read `content`, `thinking`, `tool_calls` or `error` into any output. Malformed lines and non-integer or boolean tokens are skipped, and skipped lines are counted in `k3dm_agy_transcript_skipped_lines`.
3. For each window: a session counts in `k3dm_agy_sessions` if any step falls inside the window. Tokens sum the steps inside the window, as `kind` values `input_tokens`, `cache_read_tokens` and `output_tokens`. `k3dm_agy_active_seconds` sums the gaps between consecutive in-window steps, with each gap capped at 300 s, so a session left idle for hours does not count as work.
4. Labels are `mode="unknown"` and `repo="unknown"`, because the transcript holds neither. A session is untracked unless its id equals a `session` on an `agent_exit` event in the dispatch ledger. Only `_dispatch_agy_exit` writes `agent_exit`, and those rows carry no `agent` field. Rows from before `session` was recorded have none, so they link to nothing. Read on `m4-air` 2026-11-06: 2 `agent_exit` rows, 1 with a session, and that session names a real brain directory. Corrected 2026-11-06: this said `exit` with `agent` agy, which no producer writes; Luna caught it.
5. When the brain directory exists, it is the only source of these series, so a wrapper-recorded run is not counted twice. When it does not exist, today's `agy.jsonl` path runs unchanged. The wrapper stays for dispatch linkage.
6. Emit `k3dm_agy_source_present{host="<short hostname>",source="transcripts|ledger|none"} 1` on every render, and `k3dm_agy_latest_step_timestamp` when a step was seen. Absence never emits a zero session count.
7. Add one stat panel, `agy data source`, at x 12, y 60, w 6, h 8, showing the host and source, with `none` shown as a warning. The panel must display the host and source text, not the series value `1`. Its description says what the row covers: the host named, interactive and print sessions, no combining across hosts.
8. `make machine-check` (or `--check` in `bin/k3dm-machine-setup`) reports `agy wrapper: absent` as a warning that does not fail, never as the data source.

## Files

- `bin/k3dm-dispatch-metrics`
- `bin/k3dm-machine-setup`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `docs/guides/grafana-dashboards/k3dm-agent-activity.md`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not copy `~/.gemini/antigravity` or `antigravity-cli` content, credentials or message text anywhere, including test fixtures.
- Do not run `agy` to create data. Do not install the wrapper.
- Do not push from tests: `K3DM_DISPATCH_PUSHGATEWAY_URL` is `http://127.0.0.1:9`, and the test asserts it.
- Fixtures use the step shape recorded above, with host and date in a comment and invented, content-free values.

## Acceptance

```yaml
must:
  - id: M1
    text: "With a brain directory holding a transcript whose steps fall inside a window, the render reports that session in k3dm_agy_sessions, the in-window token sum by kind in k3dm_agy_tokens, and active seconds with each gap capped at 300."
  - id: M2
    text: "A step outside a window adds nothing to that window, and a session spanning the boundary counts only its in-window tokens and active time."
  - id: M3
    text: "A session whose id appears as `session` on an `agent_exit` event in the dispatch ledger, a row that has no `agent` field, is not counted in k3dm_agy_untracked_sessions; any other session is."
  - id: M4
    text: "k3dm_agy_source_present reports the host and source: transcripts when the brain directory exists, ledger when only agy.jsonl exists, none when neither does."
  - id: M5
    text: "The dashboard has an `agy data source` panel reading k3dm_agy_source_present, overlapping no other panel, and set to display the series name (host and source) instead of the value."
  - id: M6
    text: "With no brain directory, the existing agy.jsonl metrics are the same as before the fix."
must_not:
  - id: N1
    text: "A marker placed in content, thinking, tool_calls or error never appears in the rendered metrics (paired control: M1 shows the same transcript's tokens do appear)."
  - id: N2
    text: "With neither source, no k3dm_agy_sessions or k3dm_agy_tokens series is emitted as zero, and the render still succeeds (paired control: M1)."
  - id: N3
    text: "With both a transcript and an agy.jsonl row for the same run, the session is counted once."
  - id: N4
    text: "Malformed lines, bytes that are not valid UTF-8, booleans or strings in token fields, and an unreadable transcript do not abort the render and add nothing to the token totals; skipped lines are counted."
evidence:
  - {id: E1, proves: [M1, M2, M3, M4, M6, N1, N2, N3, N4], kind: offline, text: "bin/k3dm-dispatch-metrics --dry-run with scratch HOME, K3DM_AGY_BRAIN_DIR, K3DM_AGENT_LEDGER_DIR and K3DM_WORKTREE_ROOT, asserted first. M1 to M4 red on the pre-fix commit; N1 to N4 red by mutants."}
  - {id: E2, proves: [M5], kind: offline, text: "The dashboard JSON parsed from the YAML: panel present with that query, and no two panels overlap."}
  - {id: E3, proves: [M1, M4], kind: live, text: "Claude runs the dry-run on the M4 with no push and compares session and token totals with an independent read of the transcripts, printing counts only. The operator confirms the row on Grafana after the next push."}
interface:
  - "bin/k3dm-dispatch-metrics --dry-run"
  - "env: HOME, K3DM_AGY_BRAIN_DIR, K3DM_AGENT_LEDGER_DIR, K3DM_WORKTREE_ROOT, K3DM_DISPATCH_PUSHGATEWAY_URL"
  - "transcript path: <brain>/<session id>/.system_generated/logs/transcript_full.jsonl"
  - "metrics: k3dm_agy_sessions, k3dm_agy_untracked_sessions, k3dm_agy_active_seconds, k3dm_agy_tokens, k3dm_agy_source_present, k3dm_agy_latest_step_timestamp, k3dm_agy_transcript_skipped_lines"
  - "dashboard: scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml"
```
