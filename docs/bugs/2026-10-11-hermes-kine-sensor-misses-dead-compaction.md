# Bug: Hermes cannot tell that hub kine compaction has died, and nothing alerts on it

**Filed:** 2026-10-11
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN — spec ready (v1.43.2)
**Approval:** explicit 2026-10-11 "yes" (to "Want me to file it?")
**Priority:** P2 — the datastore degrades for days unnoticed; the workaround is reading `docker logs` by hand
**Severity:** medium — the third dead-compaction episode; each one has ended in a hub rebuild

## Symptom

On 2026-10-11 the operator noticed `kine` degraded in the Hermes status table. Read-only checks
showed compaction had died on 2026-10-08 at 11:28:34Z: zero `msg="COMPACT` lines since then, and
`state.db` at 2.0 GB and growing (see the "Recurrence — 2026-10-08" section of
[`2026-09-09-hub-kine-compaction-stall.md`](2026-09-09-hub-kine-compaction-stall.md)). No alert had
fired in the 3.5 days before that.

## Root cause

1. **The sensor only sees a 20-minute log window** (`_datastore_run` in `bin/k3dm-hermes`,
   `K3DM_HERMES_KINE_LOG_WINDOW` default `20m`). `compaction_failed` is true only while the single
   `Compact failed` line is inside that window. After that, a dead loop looks like this:
   `compaction_recent=False, compaction_failed=False`.
2. **The sensor's degraded test requires Slow SQL** (`kine` in `scripts/lib/hermes/sensors.py`):
   `raw = db_bytes >= max_db_bytes or failed or (slow_sql > 0 and not compacting)`. In a quiet
   20-minute window with no Slow SQL, a dead loop reports **healthy**. The status row flickers with
   load, not with the actual fault.
3. **Nothing alerts.** Sensor records go to the `hermes-status` ConfigMap and the dashboard, and
   Hermes pages only on correlated incidents. There is no Prometheus series for compaction, so no
   rule can fire. The 2026-09-20 deep dive named the right signal ("ask when the last
   `msg="COMPACT deleted"` was; more than ~15 minutes means the loop is dead"), but it was never
   built.

Healthy kine compacts every 5 minutes (288 cycles a day, each one logs three `COMPACT` lines).

## Fix

### 1. `bin/k3dm-hermes`, `_datastore_run`

- Also run `docker logs --since 6h <container>` and take the timestamp of the **last** line that
  contains `msg="COMPACT deleted` (case-sensitive; never match `compact` alone, since Slow SQL
  text embeds `compact_rev_key`).
- Persist it in Hermes state as `kine_last_compaction_ts`. When the 6 h log contains none, keep the
  stored value. When there is no stored value, use the container's start time from
  `docker inspect -f '{{.State.StartedAt}}'` (a fresh server has had no chance to compact yet).
- Add `last_compaction_ts` (epoch seconds) and `container_started_ts` to the returned JSON.
  Existing fields are unchanged.

### 2. `scripts/lib/hermes/sensors.py`, `kine`

- Add `max_compaction_age=900` (seconds). `stalled = now - last_compaction_ts > max_compaction_age`
  when `last_compaction_ts` is present. Absent (an older probe) keeps today's behaviour.
- `raw = db_bytes >= max_db_bytes or failed or stalled or (slow_sql > 0 and not compacting)`.
- Evidence gains `last_compaction_age=<N>s`; `data` gains `last_compaction_ts`.
- Debounce unchanged (`threshold=2`).

### 3. Metrics and alert

- Each status cycle, Hermes PUTs to `job/k3dm-hub-kine` on the hub Pushgateway (same URL default
  and env pattern as `bin/k3dm-disk-metrics`; env `K3DM_KINE_PUSHGATEWAY_URL`):
  - `k3dm_hub_kine_last_compaction_timestamp_seconds`
  - `k3dm_hub_kine_state_db_bytes`
  - Skip the push when the probe is unavailable; never push zeros.
- `scripts/etc/argocd/platform-ops/prometheusrule.yaml`, group `hermes`:

  ```yaml
  - alert: HubKineCompactionStalled
    expr: time() - k3dm_hub_kine_last_compaction_timestamp_seconds > 1800
    for: 15m
    labels:
      group: hermes
      severity: warning
      cluster: hub
    annotations:
      summary: "Hub kine has not compacted in over 30 minutes"
      description: "Healthy kine compacts every 5 minutes. A dead compaction loop never restarts and state.db grows until the hub is rebuilt. Do NOT restart the k3s server (it can crash-loop the bootstrap); see docs/bugs/2026-09-09-hub-kine-compaction-stall.md."
  ```

  It routes like the other `group: hermes` warnings (email, `platform-warning`). The 30 minutes
  plus 15 minutes absorbs the first cycles after the M4 wakes.

### 4. Docs

- `docs/guides/grafana-dashboards.md` or the Hermes guide that documents the `kine` row: the new
  stall rule, the 15-minute sensor threshold and the alert.
- `docs/howto/hub-rebuild-from-gitops-vault.md`: "Dead kine compaction" names the alert as the
  trigger for a planned rebuild and repeats the do-not-restart warning.
- `CHANGELOG.md` `[Unreleased]`.

## Files

| File | Change |
|---|---|
| `bin/k3dm-hermes` | `_datastore_run` last-compaction timestamp, state persistence, metrics push |
| `scripts/lib/hermes/sensors.py` | `kine` stall test |
| `scripts/etc/argocd/platform-ops/prometheusrule.yaml` | `HubKineCompactionStalled` |
| `scripts/tests/hermes/test_hermes.py` | sensor and probe tests |
| `scripts/tests/plugins/hermes_alert_rules.bats` | rule assertions |
| `docs/howto/hub-rebuild-from-gitops-vault.md`, Hermes guide | sections above |
| `CHANGELOG.md` | `[Unreleased]` entry |

## Tests

`scripts/tests/hermes/test_hermes.py`:
- Dead loop in a quiet window (no Slow SQL, no COMPACT, `last_compaction_ts` 1 h old) → degraded
  after the debounce. Before the fix this case is healthy; prove it against the pre-fix source.
- Last compaction 4 minutes old with Slow SQL present → healthy.
- A probe without `last_compaction_ts` behaves as today (existing tests unchanged).
- Probe parsing: a log whose only "compact" text is inside a Slow SQL line yields no timestamp; a
  log with two `COMPACT deleted` lines yields the later one; an empty 6 h log keeps the stored
  state value; no state and no line falls back to the container start.
- The metrics push goes to a stub URL (autouse `127.0.0.1:9`-style fixture). No test may reach the
  real hub Pushgateway.

`hermes_alert_rules.bats`: `HubKineCompactionStalled` exists in group `hermes` with
`severity: warning`, `for: 15m`, and an expr on `k3dm_hub_kine_last_compaction_timestamp_seconds`.

Mutations (each must turn a test red): drop `stalled` from `raw`; match `compact` case-insensitively;
take the first `COMPACT deleted` line instead of the last.

## Proof it works

On the current hub (compaction dead since 2026-10-08), with the fix running before the rebuild:
the `kine` row reads degraded with `last_compaction_age` above 3 days in every cycle, not only in
cycles with Slow SQL. `HubKineCompactionStalled` fires within 15 minutes of the rule loading and
emails once. After the rebuild, the age stays under 10 minutes and the alert resolves.

## What NOT to Do

- Do NOT restart the k3s server or the container from Hermes or any repair; this stays read-only.
- Do NOT open, copy or query `state.db` with SQLite; size is read with `wc -c` as today.
- Do NOT page by SMS for this rule; it is a warning.
- Do NOT push to the hub Pushgateway from a test.
