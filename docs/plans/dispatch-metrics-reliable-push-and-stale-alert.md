# Dispatch metrics: single-flight push, retries, periodic re-push, and a stale alert

**Status:** OPEN — spec written 2026-11-18; revised the same day after Fable + Astra blind review (see Review)
**Bug:** `docs/bugs/2026-11-18-dispatch-metrics-push-times-out-silently.md` (P2)
**Branch:** `k3d-manager-v1.45.0` (bug fix, not a v1.45.0 plan; no version prefix)
**Risk:** medium (dispatch tooling, a new launchd agent, a hub alert rule)
**Worker:** Flash (`agy`, `gemini-3.8-flash-medium`)

## Why

Ledger-event pushes from the M4 to the hub Pushgateway time out (38 `dispatch metrics push failed: timed out` lines in
`metrics.log`), the dispatch dashboards go stale, and nothing alerts. An uncontended PUT of the full 3.3 MB body takes
1.2 s (measured below), so the 5 s timeouts come from contention: the Python ledger writer starts the exporter outside
the single-flight lock, and a burst of events runs several 45 s CPU-bound exporters and several 3.3 MB PUTs at once.
There is also no retry, no later re-push, and no alert.

The Hermes diagnose-and-approve flow for stale metrics is **out of scope**: it is part 5 of
`docs/plans/v1.45.0-dispatch-stall-recovery.md` (operator, 2026-11-18, option (a)).

## Facts the worker can rely on

- **Measured (Claude, M4 -> hub over the ssh tunnel, 2026-11-18 13:28 UTC):** `bin/k3dm-dispatch-metrics --dry-run`
  real 45.3 s (user 41.7 s), 3,316,618 bytes; three PUTs of that body to `localhost:19094/metrics/job/k3dm-dispatch`:
  200 in 1.21 s, 1.18 s, 1.29 s.
- Paths: `_dispatch_script_dir` is the directory of the running `bin/k3dm-codex-dispatch` (`bin/k3dm-codex-dispatch:5`).
  `_dispatch_repo_root` is `git rev-parse --show-toplevel` of the **caller's cwd** (`:6-7`), which is what the Python
  heredoc receives as `manager` (`:379`, `:383`). In BATS, `dispatch()` runs from a fixture repo with no `bin/`
  (`scripts/tests/bin/codex_dispatch_helpers.bash:103`), so `manager/bin/...` does not exist there.
- Bash single-flight scheduler `_dispatch_schedule_metrics` (`bin/k3dm-codex-dispatch:96-129`): mkdir lock
  `$_dispatch_worktree_root/metrics.lock`, `metrics.pending` coalescing, takeover when the lock dir's mtime is over
  10 minutes old (`:100`), runs `${K3DM_DISPATCH_METRICS_BIN:-$_dispatch_script_dir/k3dm-dispatch-metrics}` (`:121`) in a
  background subshell, output appended to `metrics.log`. The lock mtime is set once at `mkdir` and never refreshed, so a
  live owner whose runs (render 45 s + retries + up to 300 s log shipping, repeated for each pending request) exceed
  10 minutes gets taken over. Existing tests: `scripts/tests/bin/codex_dispatch_metrics.bats:6-28`; the overlap-detecting
  metrics stub (writes `METRICS_STARTS`, `METRICS_OVERLAP`, sleeps) is `codex_dispatch_helpers.bash:9-18`.
- Python ledger writer bypass: `bin/k3dm-codex-dispatch:485-486` —
  `subprocess.Popen([os.environ.get('K3DM_DISPATCH_METRICS_BIN', str(Path(manager)/'bin/k3dm-dispatch-metrics'))], ..., start_new_session=True)`,
  inside `append()` (`:473`) of the `_dispatch_s1` heredoc (`:377`). `release-merged` appends without scheduling (`:641`).
- Subcommand table: `bin/k3dm-codex-dispatch:1844-1857`. Usage text: near `:365`.
- Push: `bin/k3dm-dispatch-metrics:2975-2991` — `urlopen(request, timeout=5)`, one attempt, prints
  `dispatch metrics push failed: {exc}`, returns 1; on success runs `k3dm-dispatch-logs` (`subprocess.run(..., timeout=300)`,
  `:2986-2990`), which posts to `K3DM_DISPATCH_LOKI_URL`, default `http://localhost:19100` (`bin/k3dm-dispatch-logs:150`),
  i.e. the live tunnel. The exporter takes no positional argument (`:2950`); `make dispatch-metrics` (`Makefile:560-561`)
  runs it directly and `bin/k3dm-orbstack-upgrade:133` consumes that target's exit status.
- launchd: copy `scripts/etc/launchd/com.k3d-manager.dispatch-stall-watch.plist.tmpl` and Makefile
  `install-dispatch-stall-watch` (`Makefile:89-102`) / `uninstall-dispatch-stall-watch` (`:103-106`), `.PHONY` at `:39`,
  honouring `K3DM_AGENT_LOAD=0`. launchd kills leftover processes in the job's process group when the job exits unless
  `AbandonProcessGroup` is true (`man launchd.plist`, macOS 26.5.2, M4, 2026-11-18); `schedule-metrics` returns while its
  subshell runs, so the plist **must** set it. Inventory tests require every `install-*` target and every launchd label
  to be classified: `scripts/tests/bin/machine_setup.bats:264`, `scripts/tests/bin/agent_classification.bats:8-22`;
  copy the stall-watch rows at `scripts/etc/machine/not-installed.list:38-39`. Install test pattern:
  `scripts/tests/bin/dispatch_stall_watch_install.bats`.
- Hub Prometheus series (Claude, read-only, m5-air hub, 2026-11-18 13:24-13:29 UTC, `127.0.0.1:19091/api/v1/query`):
  `push_time_seconds{job="k3dm-dispatch"}` (labels `__name__`, `job` only); `k3dm_disk_probe_success{host="m4",job="k3dm-disk",path="/System/Volumes/Data"}`
  = 1, and `min_over_time(...[1h])` = 1 for every hour of the last 48 h (the hub probes the M4 over ssh; 0 or absent means
  the hub cannot reach the M4).
- Alert rules: `scripts/etc/argocd/platform-ops/prometheusrule.yaml` (shape: `HermesNotRunning`, `:205-214`). Precedents
  wrap the series in `max(...)` (`scripts/etc/prometheus/rules/host-disk.yaml:32`, `vectordb.yaml:16`). Alertmanager
  routes `severity = warning` to `platform-warning` (`scripts/etc/prometheus/alertmanager.yaml.tmpl:31-34`, 10 m
  group_wait), so **no Alertmanager change**. promtool unit-test pattern: `scripts/tests/plugins/grafana_dashboard_pr_checks.bats:~260-283`
  with `k3dm_promtool` from `scripts/tests/promtool.bash`.
- Dashboard text that becomes wrong: the "Last update" panel description in
  `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml:1082` ("a large value means no wrapped dispatch
  since, not a broken exporter").

## Changes

1. **`bin/k3dm-codex-dispatch`**
   - New subcommand `schedule-metrics`: takes no arguments (any argument is a usage error, non-zero), calls
     `_dispatch_schedule_metrics`, exits 0. Add it to the usage text.
   - `_dispatch_s1`: pass the dispatcher's own path to Python as environment, e.g. prefix the call with
     `K3DM_DISPATCH_SELF="$_dispatch_script_dir/k3dm-codex-dispatch" python3 - ...` (do not change the positional argv).
     In `append()` replace the Popen target with `[os.environ['K3DM_DISPATCH_SELF'], 'schedule-metrics']` (same
     DEVNULL, `start_new_session=True`). Do not wrap it in a try/except that hides a missing file.
   - `_dispatch_schedule_metrics`: while the subshell owns the lock, keep the lock fresh: start a background
     `while sleep 60; do touch "$lock"; done` before each exporter run and kill it after (and in the EXIT cleanup). The
     10-minute takeover then only applies to a dead owner. Keep coalescing and existing behaviour otherwise.
2. **`bin/k3dm-dispatch-metrics`** push (`:2975-2991`)
   - `K3DM_DISPATCH_PUSH_TIMEOUT` seconds, default 30, valid 1-120; `K3DM_DISPATCH_PUSH_ATTEMPTS`, default 3, valid integer
     1-5; `K3DM_DISPATCH_PUSH_BACKOFF` seconds, default 5, valid 0-30. A missing, non-numeric, non-finite or out-of-range
     value uses the default (no error).
   - Between attempts sleep `backoff * attempt_number` (use `time.sleep` so tests can patch it). Do not retry an HTTP 4xx.
   - Each failed attempt prints one line: `<UTC ISO-8601 timestamp> dispatch metrics push failed (attempt N/M): <detail>`;
     detail is `HTTP <code>` for an HTTPError, else the exception text. After the last failure return 1 without running
     the log shipper. On success return 0 and run `k3dm-dispatch-logs` exactly once, as today.
3. **`scripts/etc/launchd/com.k3d-manager.dispatch-metrics.plist.tmpl`** (new): label `com.k3d-manager.dispatch-metrics`;
   `ProgramArguments` `{{REPO_ROOT}}/bin/k3dm-codex-dispatch`, `schedule-metrics`; same `PATH` as the stall-watch plist;
   `RunAtLoad` true; `StartInterval` 900; `AbandonProcessGroup` true; stdout/stderr
   `{{HOME}}/.local/share/k3d-manager/logs/dispatch-metrics.log`.
4. **`Makefile`**: `install-dispatch-metrics` / `uninstall-dispatch-metrics` copied from the stall-watch targets (messages
   name the new label; `K3DM_AGENT_LOAD=0` writes the plist without loading), added to `.PHONY`. `make dispatch-metrics`
   is unchanged (synchronous, direct, exit status kept).
5. **`scripts/etc/machine/not-installed.list`**: two rows after `:39`, `install-dispatch-metrics|operator-run: make install-dispatch-metrics on the machine that runs dispatches; 15-minute dispatch-metrics re-push (docs/plans/dispatch-metrics-reliable-push-and-stale-alert.md, live E5)`
   and `dispatch-metrics|operator-run LaunchAgent on the machine that runs dispatches, loaded by make install-dispatch-metrics (live E5)`.
6. **`scripts/etc/argocd/platform-ops/prometheusrule.yaml`**: new group `dispatch.alerts`:
   ```yaml
   - alert: DispatchMetricsStale
     expr: |
       (
         max by (job) (time() - push_time_seconds{job="k3dm-dispatch"}) > 3600
         or absent(push_time_seconds{job="k3dm-dispatch"})
       )
       and on() max(k3dm_disk_probe_success{host="m4"}) == 1
     for: 30m
     labels: {group: dispatch, severity: warning, cluster: hub}
     annotations:
       summary: "Dispatch metrics have not reached the hub for over 90 minutes while the M4 is reachable"
       description: "The M4 pushes dispatch metrics after dispatch ledger events and every 15 minutes (LaunchAgent com.k3d-manager.dispatch-metrics). Check ~/.local/share/k3d-manager/worktrees/metrics.log and ~/.local/share/k3d-manager/logs/dispatch-metrics.log on the M4, and the com.k3d-manager.hub-pushgateway-port-forward tunnel. See docs/bugs/2026-11-18-dispatch-metrics-push-times-out-silently.md."
   ```
   Timing: a present series fires about 90 minutes after the last push (60 m threshold + 30 m hold), plus up to 10 m
   Alertmanager group wait. It does not fire while the hub cannot reach the M4 (asleep, off, away).
7. **`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml:1082`**: "Last update" description now says
   the exporter runs after dispatch ledger events, every 15 minutes from the `com.k3d-manager.dispatch-metrics`
   LaunchAgent, or on `make dispatch-metrics`; over about 20 minutes means pushes are failing (see `DispatchMetricsStale`).
   Text only; keep thresholds and JSON validity.
8. **Docs**: one paragraph in `docs/guides/grafana-dashboards/k3dm-agent-dispatch.md` (agent, make targets, alert);
   `schedule-metrics` in `docs/howto/codex-dispatch.md`; `CHANGELOG.md` line under `[Unreleased]` Fixed.

## Files

- `bin/k3dm-codex-dispatch`
- `bin/k3dm-dispatch-metrics`
- `scripts/etc/launchd/com.k3d-manager.dispatch-metrics.plist.tmpl`
- `Makefile`
- `scripts/etc/machine/not-installed.list`
- `scripts/etc/argocd/platform-ops/prometheusrule.yaml`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/bin/codex_dispatch_metrics.bats`
- `scripts/tests/bin/dispatch_metrics_install.bats`
- `scripts/tests/plugins/dispatch_alert_rules.bats`
- `docs/guides/grafana-dashboards/k3dm-agent-dispatch.md`
- `docs/howto/codex-dispatch.md`
- `CHANGELOG.md`
- `scripts/tests/bin/codex_dispatch_ledger.bats` (amended 2026-11-18 after verification: its `s1_snapshot` must wait for, or exclude, `metrics.lock`/`metrics.log` now that ledger appends start the scheduler)
- `scripts/tests/plugins/agent_dispatch_dashboard.bats` (amended 2026-11-18: add panel 9 to the exclusion set at :68-72; item 7 changes panel 9's description, a reader of the dashboard contract missed by the spec)

## Out of scope

- gzip or payload trimming (an uncontended PUT is 1.2 s; prove Pushgateway gzip support before any such change).
- Hermes cards and approval (plan 5, part 5).
- Two contenders racing to take over the same **dead** lock, and owner-specific release (pre-existing; recorded in the bug
  doc for grooming).
- Routing `make dispatch-metrics` through the lock: it stays synchronous for `bin/k3dm-orbstack-upgrade`. Known limit:
  a manual run can overlap a scheduled one; each push is full state, so the next scheduled push corrects any older
  payload that finished last.
- Installing the agent on the M4 (Claude does that after land, with the operator's go).

## Contract readers

- `K3DM_DISPATCH_METRICS_BIN` — readers: `bin/k3dm-codex-dispatch:121` (scheduler, unchanged), `:486` (Python, now
  reaches the exporter only via `schedule-metrics`, which honours it); writer in tests:
  `scripts/tests/bin/codex_dispatch_helpers.bash:9` (inherited by `codex_dispatch_ledger.bats`,
  `codex_dispatch_metrics.bats`); documented in `docs/plans/v1.43.14-*` (historical, unchanged). Meaning unchanged.
- `K3DM_DISPATCH_SELF` (new) — writer `_dispatch_s1`; reader `append()` in the same heredoc only.
- `metrics.lock` / `metrics.pending` — reader and writer `_dispatch_schedule_metrics` only, now reached from the Python
  path and the launchd agent; lock mtime is refreshed while held (new). Format unchanged.
- `metrics.log` line format — the failure line gains a timestamp and `(attempt N/M)`. No code reads it
  (`grep -rn 'push failed' bin scripts` finds only the writer).
- `make dispatch-metrics` — callers: operator, `bin/k3dm-orbstack-upgrade:133`. Behaviour unchanged except retries
  (worst case at defaults about 45 s render + 3 x 30 s + 15 s backoff + shipper).
- `push_time_seconds{job="k3dm-dispatch"}` — writer: the Pushgateway; new reader `DispatchMetricsStale`.
  `k3dm_disk_probe_success{host="m4"}` — writer: hub disk metrics; new reader `DispatchMetricsStale`.
- New launchd label `dispatch-metrics` and target `install-dispatch-metrics` — readers
  `scripts/tests/bin/machine_setup.bats:264`, `scripts/tests/bin/agent_classification.bats:8-22`.

## Acceptance

```yaml
interface:
  - "bin/k3dm-codex-dispatch schedule-metrics (new subcommand); any ledger-appending subcommand (e.g. link)"
  - "bin/k3dm-dispatch-metrics (no positional args; env K3DM_DISPATCH_PUSH_TIMEOUT / _ATTEMPTS / _BACKOFF; stdout failure lines)"
  - "make install-dispatch-metrics / uninstall-dispatch-metrics; scripts/etc/launchd/com.k3d-manager.dispatch-metrics.plist.tmpl"
  - "scripts/etc/argocd/platform-ops/prometheusrule.yaml alert DispatchMetricsStale"
must:
  - id: M1
    text: ledger events appended by the Python path start the exporter only through the single-flight lock, from a caller cwd that has no bin/ directory; a burst of such events runs the exporter at least once and never two at once
  - id: M2
    text: a push that fails then succeeds exits 0 and runs the log shipper once; all attempts failing exits 1 after exactly ATTEMPTS tries, sleeping backoff*attempt between them, and never runs the shipper; an HTTP 4xx is tried once
  - id: M3
    text: the default push timeout is 30 s; valid env overrides are honoured; invalid or out-of-range values fall back to the defaults
  - id: M4
    text: each failed attempt logs one line with a UTC timestamp, attempt N/M, and HTTP code or exception text
  - id: M5
    text: a live lock owner whose run lasts longer than 10 minutes keeps its lock (mtime refreshed); a dead owner's lock older than 10 minutes is still taken over; a fresh lock is still respected
  - id: M6
    text: make install-dispatch-metrics renders a plist running bin/k3dm-codex-dispatch schedule-metrics every 900 s with RunAtLoad and AbandonProcessGroup true; K3DM_AGENT_LOAD=0 writes without loading; uninstall removes it; the inventory tests pass
  - id: M7
    text: DispatchMetricsStale fires after its 30 m hold when the last push is over 3600 s old or the series is absent, only while k3dm_disk_probe_success{host="m4"} is 1; it does not fire for a fresh push or when the M4 is unreachable
must_not:
  - id: N1
    text: two exporters overlap when Python-path ledger events arrive in a burst — red today (Popen bypasses the lock)
  - id: N2
    text: one transient push failure loses the push — red today (one attempt)
  - id: N3
    text: the push uses a 5 s timeout by default — red today
  - id: N4
    text: a live owner's lock is taken over after 10 minutes — red today (mtime never refreshed)
  - id: N5
    text: no alert rule reports stale k3dm-dispatch pushes — red today
evidence:
  - id: E1
    proves: [M2, M3, M4, N2, N3]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_dispatch_metrics.py scripts/tests/bin/test_dispatch_logs.py -q
    intent: "A dispatch-metrics push that hits a slow or flaky moment retries and gets through, and when it truly fails the log says when, which attempt and why."
  - id: E2
    proves: [M1, M5, N1, N4]
    kind: offline
    command: bats scripts/tests/bin/codex_dispatch_metrics.bats scripts/tests/bin/codex_dispatch_ledger.bats
    intent: "However many dispatch events land at once, only one metrics export runs at a time, so they no longer pile up and time each other out."
  - id: E3
    proves: [M6]
    kind: offline
    command: bats scripts/tests/bin/dispatch_metrics_install.bats scripts/tests/bin/machine_setup.bats scripts/tests/bin/agent_classification.bats
    intent: "One make command installs a background job on the M4 that re-sends dispatch metrics every 15 minutes, so a missed push repairs itself."
  - id: E4
    proves: [M7, N5]
    kind: offline
    command: bats scripts/tests/plugins/dispatch_alert_rules.bats
    intent: "If dispatch metrics stop reaching the hub for about 90 minutes while the M4 is on, you get a warning email instead of a quietly stale dashboard, and no email while the M4 is asleep or away."
  - id: E5
    proves: [M6]
    kind: live
    what: "Claude, after land and operator go: make install-dispatch-metrics on the M4. With no dispatch activity, push_time_seconds{job=\"k3dm-dispatch\"} on hub Prometheus advances once at load and again 15-17 minutes later; launchctl print shows the job's last exit 0."
    intent: "With nothing dispatched, the hub's dispatch dashboard keeps showing a last-push time under about 17 minutes old."
  - id: E6
    proves: [M7]
    kind: live
    what: "Claude, after operator hub-promote and platform-ops sync: hub Prometheus /api/v1/rules lists DispatchMetricsStale in dispatch.alerts with state inactive."
    intent: "The hub knows about the new stale-metrics alert and it is quiet while pushes are healthy."
```

### Test requirements (for the worker and the independent verifier)

- **E1 isolation, asserted first:** scratch `HOME` and `K3DM_WORKTREE_ROOT`; pass `--codex-home`, `--claude-projects`,
  `--claude-cache` into scratch dirs; point `K3DM_DISPATCH_PUSHGATEWAY_URL` at a local `http.server` stub thread and assert
  the request reached the stub; monkeypatch `subprocess.run` so the real log shipper never runs (count its calls).
  Patch `time.sleep` to record arguments instead of setting backoff to 0.
- **N3:** monkeypatch `urllib.request.urlopen` to capture the `timeout` argument; with no env set it must be 30 (red today:
  5). Separate cases: a valid override (e.g. 7) is honoured; `abc`, `0`, `-1`, `inf`, `500` fall back to 30; attempts `0`,
  `9`, `x` fall back to 3; backoff `-1`, `99` fall back to 5.
- **N2 / M2:** stub fails once (connection reset or HTTP 503) then 200 -> exit 0, shipper called once, one failure line;
  always failing -> exit 1, exactly 3 requests, sleeps `[5, 10]`, shipper not called; HTTP 404 -> exactly 1 request, exit 1.
- **N1:** from the fixture repo (no `bin/`), run 4-5 distinct ledger-appending calls (`dispatch link --slug task --parent pN --role build`,
  `codex_dispatch_ledger.bats:23`, distinct `pN`) backgrounded with `&` then `wait`; confirm each ledger line was written;
  wait for `metrics.lock` to disappear; assert `METRICS_STARTS` has at least 1 line **and** `METRICS_OVERLAP` does not exist.
  Positive control in the same file: two direct concurrent stub invocations do create `METRICS_OVERLAP`. Must fail today at
  the overlap assertion.
- **N4:** with the metrics stub sleeping past a short refresh (make the refresh interval overridable for tests, e.g.
  `K3DM_DISPATCH_METRICS_LOCK_REFRESH`, default 60), age the held lock with `touch -t 202001010000` during the run and
  assert its mtime moves forward and a second scheduler call does not take it over (no second start). Keep the existing
  dead-lock takeover and fresh-lock tests passing.
- **E4:** promtool unit test (`k3dm_promtool test rules`, pattern in `grafana_dashboard_pr_checks.bats`) loading the real
  rule file, with cases: fresh push + M4 up -> no alert; stale push + M4 up -> fires after the hold, not before; absent
  series + M4 up -> fires; stale push + M4 probe 0 -> no alert; recovery -> resolves. Positive control: the same harness
  finds `HubDataExportStale` in `dr.alerts`.

## Review (2026-11-18)

Fable and Astra (codex `gpt-6.2-astra`, read-only) reviewed the first draft blind. Both found the two blockers (no
`## Files`, so `start` refuses at `bin/k3dm-codex-dispatch:1029`; `manager` is the caller's repo, so the new Popen would
break the fixture tests) and the unrefreshed lock mtime, the vacuous N1, the untestable N3, and the real log shipper in
E1. Astra also found the inventory tests, the `make dispatch-metrics` callers, env input domains, the need to test the
rule itself, the dashboard text, and the weak E5. Fable also found the `max()` precedent, the M4-asleep noise, and the
unmeasured timeout. All accepted except: owner-specific release and the dead-lock contender race (pre-existing, out of
scope) and routing `make dispatch-metrics` through the lock (kept synchronous). Claude measured the PUT (1.2 s) and
added the M4-reachable gate from the hub disk probe.

**Intent approved:** operator, 2026-11-18
**Approval words and scope:** "go ahead with your recommendation and dispatch to Flash if there is a slot for it"
(operator, 2026-11-18), after Claude proposed parts 1-3 (reliable push, 15-minute re-push, stale alert) as the P2 fix
with the Hermes flow moved to plan 5.
