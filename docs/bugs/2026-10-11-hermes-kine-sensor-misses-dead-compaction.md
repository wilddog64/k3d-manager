# Bug: Hermes cannot tell that hub kine compaction has died, and nothing alerts on it

**Filed:** 2026-10-11
**Branch:** `k3d-manager-v1.43.2`
**Status:** LIVE-VERIFIED 2026-10-11 (`6e1c82a4`, v1.43.2); live: alert fired 02:02:12Z and routed to `platform-warning`; operator confirmed the `[FIRING] HubKineCompactionStalled on hub (1)` email — live proof complete
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

- `docs/guides/hermes.md` (the guide that documents the `kine` row): the new stall rule, the
  15-minute sensor threshold and the alert.
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
| `scripts/tests/observability/test_kine_compaction_stalled.py` | new: promtool fire, delivery to `platform-warning` |
| `scripts/tests/observability/conftest.py`, `scripts/tests/observability/test_alertmanager_notify_behaviour.py` | only if `Sink` and the Alertmanager fixture move to a shared conftest |
| `scripts/tests/plugins/alertmanager_config_secret.bats` | amtool route assertion |
| `Makefile` | `test-alertmanager-behaviour` also runs the new file |
| `docs/howto/hub-rebuild-from-gitops-vault.md`, `docs/guides/hermes.md` | sections above |
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

### Targeted regression test: the alert fires, and the notification reaches its destination

Operator, 2026-10-11: "simulate a stale last-successful-compaction timestamp while the Kubernetes
API remains healthy and slow-query counts are zero. Verify that `HubKineCompactionStalled` fires and
that the notification reaches its intended destination." This is the failure that went unalerted
from 2026-10-08 to 2026-10-11, so it gets an end-to-end test, not only unit tests.

The test is a new `scripts/tests/observability/test_kine_compaction_stalled.py`. Mark it
`pytest.mark.external` like `test_alertmanager_notify_behaviour.py`, because it runs pinned images
in Docker. It has three stages and reuses that file's `Sink` and Alertmanager fixture (import them
or move them to a shared `conftest.py`; do not copy them).

1. **Rule evaluation (promtool).** Extract `spec.groups` from `prometheusrule.yaml` into a temporary
   rules file, then run `promtool test rules` from `quay.io/prometheus/prometheus:v3.1.0` (the
   version the hub runs). Input series over 60 minutes at a 1-minute interval:
   - `k3dm_hub_kine_last_compaction_timestamp_seconds` fixed at `0` (stale from the start);
   - `k3dm_hub_kine_state_db_bytes` steady at 2e9;
   - `up{job="apiserver"}` = 1 throughout (the API is healthy);
   - no slow-query series at all.

   Expected:
   - **firing** at `eval_time: 46m`, with labels `group=hermes, severity=warning, cluster=hub`;
   - **not firing** at `eval_time: 44m`, inside the `for: 15m`;
   - `KubeAPIDown` not firing at 46m, if the extracted rules include it, which proves the API was
     modelled as healthy.

   A second case advances the timestamp every 5 minutes (healthy compaction) and asserts no
   `HubKineCompactionStalled` at 60m.
2. **Routing (amtool).** Render `alertmanager.yaml.tmpl` as `alertmanager_config_secret.bats`
   does. Then `amtool config routes test alertname=HubKineCompactionStalled group=hermes
   severity=warning cluster=hub` must print exactly `platform-warning`, not `sms-critical` or
   `null`. Put this assertion in `alertmanager_config_secret.bats` next to the existing route tests.
3. **Delivery (real Alertmanager, fake receiver).** With the existing fixture (pinned
   `alertmanager:v0.27.0`, email receivers rewritten to webhooks into the `Sink`), POST the alert
   with stage 1's labels and annotations to `/api/v2/alerts`. Assert:
   - the sink receives one notification on path `/platform-warning` and none on `/sms-critical`;
   - the payload's `commonLabels.alertname` is `HubKineCompactionStalled`;
   - the description contains "Do NOT restart", so the warning reaches the reader.

Mutation: change the rule's `severity` to `critical`. Stage 1 still fires, but stages 2 and 3 must
fail (it would route to SMS). Change the threshold to `> 3600`; stage 1 must fail at 46m.

`make test-alertmanager-behaviour` runs both observability files. CI skips external tests, so the
verifier runs this target locally and pastes the result. The test never touches the real hub,
Pushgateway or Alertmanager.

**Live check after the fix lands** (in "Proof it works"): the real email arrives at the
`platform-warning` address while the current hub still has dead compaction.

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
