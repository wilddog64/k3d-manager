# Dispatch metrics: reliable push, periodic re-push, and a stale alert

**Status:** OPEN — spec written 2026-11-18
**Bug:** `docs/bugs/2026-11-18-dispatch-metrics-push-times-out-silently.md` (P2)
**Branch:** `k3d-manager-v1.45.0` (bug fix, not a v1.45.0 plan; no version prefix)
**Risk:** medium (dispatch tooling, a new launchd agent, a hub alert rule)
**Worker:** Flash (`agy`, `gemini-3.8-flash-medium`)

## Why

Ledger-event pushes from the M4 to the hub Pushgateway time out (38 `dispatch metrics push failed: timed out` lines in
`metrics.log`), the dispatch dashboards go stale, and nothing alerts. Three gaps: the push has one 5 s attempt for a
3.3 MB body; the Python ledger writer starts the exporter outside the single-flight lock, so bursts overlap; nothing
re-pushes later or alerts on staleness.

The Hermes diagnose-and-approve flow for stale metrics is **out of scope**: it is added as a second trigger to
`docs/plans/v1.45.0-dispatch-stall-recovery.md` (operator, 2026-11-18, option (a)).

## Facts the worker can rely on

- Bash single-flight scheduler: `_dispatch_schedule_metrics` (`bin/k3dm-codex-dispatch:96-129`): mkdir lock
  `$_dispatch_worktree_root/metrics.lock`, `metrics.pending` coalescing, 10-minute stale-lock takeover, runs
  `${K3DM_DISPATCH_METRICS_BIN:-$_dispatch_script_dir/k3dm-dispatch-metrics}` in a background subshell, output appended to
  `metrics.log`. Existing tests: `scripts/tests/bin/codex_dispatch_metrics.bats:6-28`.
- Python ledger writer bypass: `bin/k3dm-codex-dispatch:485-486` —
  `subprocess.Popen([os.environ.get('K3DM_DISPATCH_METRICS_BIN', str(Path(manager)/'bin/k3dm-dispatch-metrics'))], ..., start_new_session=True)`.
- Subcommand table: `bin/k3dm-codex-dispatch:1844-1856` (`start)`, `open)`, ... `release-merged)`).
- Push: `bin/k3dm-dispatch-metrics:2975-2986` — `urlopen(request, timeout=5)`, one attempt, prints
  `dispatch metrics push failed: {exc}` and returns 1. On success it runs `k3dm-dispatch-logs` (keep that).
- launchd pattern to copy: `scripts/etc/launchd/com.k3d-manager.dispatch-stall-watch.plist.tmpl` and Makefile
  `install-dispatch-stall-watch` / `uninstall-dispatch-stall-watch` (`Makefile:39`, `:89-105`, honours
  `K3DM_AGENT_LOAD=0`); test pattern `scripts/tests/bin/dispatch_stall_watch_install.bats` (stub `launchctl`, scratch HOME).
- launchd kills leftover processes in the job's process group when the job exits unless `AbandonProcessGroup` is true
  (`man launchd.plist`, macOS 26.5.2, M4, 2026-11-18). `schedule-metrics` returns while its subshell keeps running, so the
  plist **must** set `AbandonProcessGroup` true.
- Hub Prometheus already has the freshness series (Claude, read-only, m5-air hub, 2026-11-18 13:24 UTC,
  `127.0.0.1:19091/api/v1/query`): `push_time_seconds{job="k3dm-dispatch"}` with labels `__name__`, `job` only.
- Alert rule file: `scripts/etc/argocd/platform-ops/prometheusrule.yaml` (groups at `:10`, `:32`, `:84`, `:172`, `:203`,
  `:225`); shape to copy: `HermesNotRunning` (`:205-213`). Alertmanager routes `severity = warning` to
  `platform-warning` already (`scripts/etc/prometheus/alertmanager.yaml.tmpl:31-33`), so **no Alertmanager change**.
  Rule test pattern: `scripts/tests/plugins/dr_alert_rules.bats:7-16`.

## Changes

1. **`bin/k3dm-codex-dispatch`**
   - Add subcommand `schedule-metrics` (no options; error on any argument) that calls `_dispatch_schedule_metrics` and exits 0.
   - Python ledger writer (`:486`): start `[<manager>/bin/k3dm-codex-dispatch, 'schedule-metrics']` instead of the exporter
     directly (same `stdout/stderr=DEVNULL`, `start_new_session=True`). `K3DM_DISPATCH_METRICS_BIN` keeps working because
     `_dispatch_schedule_metrics` already honours it.
2. **`bin/k3dm-dispatch-metrics`** push (`:2975-2986`)
   - Timeout from `K3DM_DISPATCH_PUSH_TIMEOUT` (seconds, default 30).
   - Up to `K3DM_DISPATCH_PUSH_ATTEMPTS` attempts (default 3), sleeping `K3DM_DISPATCH_PUSH_BACKOFF` seconds (default 5)
     multiplied by the attempt number between attempts. Do not retry an HTTP 4xx response.
   - Each failed attempt prints one line: `<UTC ISO-8601 timestamp> dispatch metrics push failed (attempt N/M): <detail>`,
     where detail is `HTTP <code>` for an HTTP error, else the exception text. Final failure returns 1; success returns 0
     and still runs `k3dm-dispatch-logs`.
3. **`scripts/etc/launchd/com.k3d-manager.dispatch-metrics.plist.tmpl`** (new): label `com.k3d-manager.dispatch-metrics`,
   `ProgramArguments` `{{REPO_ROOT}}/bin/k3dm-codex-dispatch schedule-metrics`, same `PATH` as the stall-watch plist,
   `RunAtLoad` true, `StartInterval` 900, `AbandonProcessGroup` true, stdout/stderr
   `{{HOME}}/.local/share/k3d-manager/logs/dispatch-metrics.log`.
4. **`Makefile`**: `install-dispatch-metrics` / `uninstall-dispatch-metrics`, copied from the stall-watch targets
   (including `K3DM_AGENT_LOAD=0`, error messages naming the new label), added to `.PHONY` at `:39`. Do not install or load
   anything on the real machine.
5. **`scripts/etc/argocd/platform-ops/prometheusrule.yaml`**: new group `dispatch.alerts` with
   ```yaml
   - alert: DispatchMetricsStale
     expr: time() - push_time_seconds{job="k3dm-dispatch"} > 3600 or absent(push_time_seconds{job="k3dm-dispatch"})
     for: 15m
     labels: {group: dispatch, severity: warning, cluster: hub}
     annotations:
       summary: "Dispatch metrics have not reached the hub in over an hour"
       description: "The M4 pushes dispatch metrics after every ledger event and every 15 minutes (com.k3d-manager.dispatch-metrics). Check ~/.local/share/k3d-manager/worktrees/metrics.log and logs/dispatch-metrics.log on the M4, and the hub-pushgateway-port-forward tunnel. See docs/bugs/2026-11-18-dispatch-metrics-push-times-out-silently.md."
   ```
6. **Docs**: one paragraph in `docs/guides/grafana-dashboards/k3dm-agent-dispatch.md` naming the agent, its make
   targets, and the alert. `CHANGELOG.md` line under
   `[Unreleased]` Fixed.

## Out of scope

gzip or payload trimming (needs proof the deployed Pushgateway accepts gzip first); Hermes cards; changing the 10-minute
stale-lock threshold; installing the agent on the M4 (Claude does that after land, with the operator's go).

## Contract readers

- `K3DM_DISPATCH_METRICS_BIN` — readers: `bin/k3dm-codex-dispatch:121` (scheduler), `:486` (Python, changes to go via the
  scheduler); tests that set it: `scripts/tests/bin/codex_dispatch_helpers.bash`, `codex_dispatch_ledger.bats`. Meaning
  unchanged.
- `metrics.lock` / `metrics.pending` — writer and reader: `_dispatch_schedule_metrics` only; now also reached from the
  Python path and the launchd agent. Format unchanged.
- `push_time_seconds{job="k3dm-dispatch"}` — writer: Pushgateway itself; new reader: `DispatchMetricsStale`.
- New env vars `K3DM_DISPATCH_PUSH_TIMEOUT`, `K3DM_DISPATCH_PUSH_ATTEMPTS`, `K3DM_DISPATCH_PUSH_BACKOFF` — reader
  `bin/k3dm-dispatch-metrics` only.

## Acceptance

```yaml
interface:
  - "bin/k3dm-codex-dispatch schedule-metrics (new subcommand)"
  - "bin/k3dm-dispatch-metrics push (env K3DM_DISPATCH_PUSH_TIMEOUT / _ATTEMPTS / _BACKOFF; stdout failure lines)"
  - "make install-dispatch-metrics / uninstall-dispatch-metrics; scripts/etc/launchd/com.k3d-manager.dispatch-metrics.plist.tmpl"
  - "scripts/etc/argocd/platform-ops/prometheusrule.yaml group dispatch.alerts"
must:
  - id: M1
    text: a ledger event written by the Python path starts the exporter through the single-flight lock; a burst of such events never runs two exporters at once
  - id: M2
    text: a push that fails then succeeds on a later attempt exits 0; three failures exit 1 after three attempts; an HTTP 4xx is not retried
  - id: M3
    text: each failed attempt logs one line with a UTC timestamp, attempt N/M, and HTTP code or exception text
  - id: M4
    text: make install-dispatch-metrics renders a plist that runs bin/k3dm-codex-dispatch schedule-metrics every 900 s with AbandonProcessGroup true; uninstall removes it; K3DM_AGENT_LOAD=0 writes without loading
  - id: M5
    text: DispatchMetricsStale exists in group dispatch.alerts with severity warning and fires on a push older than 3600 s or a missing series
  - id: M6
    text: existing scheduler tests (coalescing, stale-lock takeover, fresh-lock respect) still pass
must_not:
  - id: N1
    text: overlapping exporters from a burst of Python-path ledger events — red today (Popen bypasses the lock)
  - id: N2
    text: a single transient push failure loses the push — red today (one attempt)
  - id: N3
    text: the push gives up after 5 s by default — red today
  - id: N4
    text: no alert rule reads push_time_seconds for k3dm-dispatch — red today
evidence:
  - id: E1
    proves: [M2, M3, N2, N3]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_dispatch_metrics.py -q -k "push"
    intent: "A dispatch-metrics push that hits a slow or flaky moment retries and gets through, and when it truly fails the log says when, which attempt and why."
  - id: E2
    proves: [M1, M6, N1]
    kind: offline
    command: bats scripts/tests/bin/codex_dispatch_metrics.bats scripts/tests/bin/codex_dispatch_ledger.bats
    intent: "However many dispatch events land at once, only one metrics export runs at a time, so they no longer pile up and time each other out."
  - id: E3
    proves: [M4]
    kind: offline
    command: bats scripts/tests/bin/dispatch_metrics_install.bats
    intent: "One make command installs a background job on the M4 that re-sends dispatch metrics every 15 minutes, so a missed push repairs itself."
  - id: E4
    proves: [M5, N4]
    kind: offline
    command: bats scripts/tests/plugins/dispatch_alert_rules.bats
    intent: "If dispatch metrics stop reaching the hub for an hour, you get a warning email instead of a quietly stale dashboard."
  - id: E5
    proves: [M1, M4]
    kind: live
    what: "Claude, after land and operator go: make install-dispatch-metrics on the M4; within 20 min push_time_seconds{job=\"k3dm-dispatch\"} on hub Prometheus advances with no dispatch activity, and metrics.log shows no overlapping runs."
    intent: "With nothing dispatched, the hub's dispatch dashboard still shows a last-push time under 15 minutes old."
  - id: E6
    proves: [M5]
    kind: live
    what: "Claude, after operator hub-promote and platform-ops sync: hub Prometheus /api/v1/rules lists DispatchMetricsStale in dispatch.alerts, state inactive."
    intent: "The hub knows about the new stale-metrics alert and it is quiet while pushes are healthy."
```

Test notes for the worker: stub the Pushgateway with a local `http.server` thread in the pytest (failure-then-success,
always-fail, 404); set `K3DM_DISPATCH_PUSH_BACKOFF=0` in tests. For N1, drive the Python ledger writer (an existing
ledger test entry point) several times in quick succession with `K3DM_DISPATCH_METRICS_BIN` pointing at the existing
overlap-detecting stub from `codex_dispatch_helpers.bash`, and assert no overlap file. E4 has a positive control: the same
assertion helper finds `HubDataExportStale` in `dr.alerts`. Every `must_not` test must fail on the pre-fix tree.

**Intent approved:** operator, 2026-11-18
**Approval words and scope:** "go ahead with your recommendation and dispatch to Flash if there is a slot for it"
(operator, 2026-11-18), after Claude proposed parts 1-3 (reliable push, 15-minute re-push, stale alert) as the P2 fix
with the Hermes flow moved to plan 5.
