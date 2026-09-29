# Bug: Hermes `node_pressure` measures webhook service failures, not node pressure

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-29 by Claude (cloud session), from the operator's Hermes Status dashboard
**Status:** OPEN — spec only
**Severity:** Medium — misleading on the dashboard, double-counts other sensors, and blocks self-repair R2
**Component:** `scripts/lib/hermes/sensors.py` (`node_pressure`), `scripts/lib/hermes/repairs.py`

## Evidence (2026-09-29, first day the dashboard had data)

The Hermes Status table showed five degraded sensors. Three of them were the same two faults:

| Sensor | Evidence |
|---|---|
| `reachability` | `single-service 1/7 hosts failing` (`frontend.3ai-talk.org`) |
| `eso` | `1/8 not synced: cosign-public-key` |
| `node_pressure` | `webhook failures: Frontend, Product images, Hub ESO ExternalSecrets` |

`node_pressure` added no information: its evidence is the frontend outage and the ESO failure again.

## The defect

`node_pressure` (`sensors.py:170`) never reads node conditions, pressure taints, or kubelet
signals. It reads the webhook's per-service smoke list and degrades when the `Data layer` check
fails **or any two services fail** (`service_threshold=2`). So:

1. **Misnamed.** An operator reading "node_pressure degraded" looks at nodes; the cause is in
   services. No node was under pressure on 2026-09-29.
2. **Double-counts.** Any fault already reported by `reachability` or `eso` also shows up in the
   webhook service list, so two faults read as three degraded sensors, and the correlator sees a
   broader incident than exists.
3. **Blocks R2.** `repairs._r2_precondition` restarts a single broken port-forward only when
   `node_pressure == "healthy"`, meaning "the platform is otherwise fine". But the failing service
   that R2 should repair is itself counted by `node_pressure`, and one more unrelated failure (here
   ESO) is enough to cross the threshold. R2 is disabled in the situation it was written for.

`pager.WEBHOOK_SENSORS = ("eso", "node_pressure")` and `repairs._unknown_webhook` use
`node_pressure`'s *unknown* state as "the webhook is unreachable". That use is legitimate and must
be kept.

## Fix — proposed, needs the operator's choice

- **(a) Rename and narrow, preferred.** Rename to `data_layer` and degrade only on the `Data layer`
  check, which is its one signal not covered elsewhere. Keep its `unknown` path, so
  `WEBHOOK_SENSORS` and `_unknown_webhook` behave the same. Change `_r2_precondition` to require
  `data_layer == "healthy"`. Update the dashboard's sensor list, `target_scopes` in the exporter,
  and `docs/guides/hermes.md`.
- **(b) Make it real.** Keep the name and read node conditions (`MemoryPressure`, `DiskPressure`,
  `PIDPressure`, `Ready`) from the hub and app contexts, and add a separate `data_layer` sensor.
  More value; more work, and a new kubectl dependency in Hermes.

Either way, the "two or more services failed" rule goes away: each service failure already belongs
to the sensor that owns it.

## Tests (for whichever option)

1. Webhook list with `Frontend` and `Hub ESO ExternalSecrets` failing, `Data layer` ok → the
   renamed/narrowed sensor is `healthy`.
2. `Data layer` failing → degraded (after debounce).
3. Webhook unreachable → `unknown` with "source unavailable", and `_unknown_webhook` still true.
4. R2 precondition with a single failing port-forward host, `Data layer` ok, and an unrelated ESO
   failure → true.

### Mutations

- Restore the two-service rule → test 1 red.
- Make R2 depend on the old aggregate → test 4 red.
