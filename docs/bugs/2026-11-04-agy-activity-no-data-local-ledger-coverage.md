# Bug: Agent Activity agy panels show No data without identifying missing telemetry source

**Filed:** 2026-11-04
**Branch:** `k3d-manager-v1.43.14`
**Status:** OPEN — static source investigation complete; live M5/M2 collector and wrapper inspection pending
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
