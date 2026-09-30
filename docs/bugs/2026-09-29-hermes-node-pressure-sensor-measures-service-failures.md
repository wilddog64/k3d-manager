# Bug: Hermes `node_pressure` measures webhook service failures, not node pressure

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-29 by Claude (cloud session), from the operator's Hermes Status dashboard
**Status:** OPEN — assigned to Codex 2026-09-30 (brief below, option (a))
**Severity:** Medium — misleading on the dashboard, double-counts other sensors, and blocks self-repair R2
**Component:** `scripts/lib/hermes/sensors.py` (`node_pressure`), `scripts/lib/hermes/repairs.py`

## Codex brief

**Goal:** the sensor that today reads "node_pressure" reports only what no other sensor covers, the
webhook's `Data layer` check, under an honest name, and R2 is no longer blocked by failures that
belong to other sensors.

**Runs where:** Codex web is fine. Pure Python and docs; all tests are offline.

**Decision:** option (a), recommended by Claude and handed off by the operator on 2026-09-30. Rename
`node_pressure` → `data_layer` and narrow it. Do **not** implement option (b) (real node conditions).

**Files to touch (only these):**
- `scripts/lib/hermes/sensors.py`: rename `node_pressure` → `data_layer`. Keep the signature minus
  `service_threshold`. Keep the `unknown` paths exactly ("source unavailable" wording, and
  `_unavailable` when there's no token). Degrade (debounced, `threshold=2` as today) **only** when
  the `Data layer` service is `ok is False`, with evidence `data layer: <its detail>`. Other failing
  services no longer affect it. If there's no `Data layer` entry at all → `unknown`
  ("data layer check absent from webhook payload"). `Data layer` with `ok is None` (the webhook
  reports "not deployed (namespace shopping-cart-data absent …)", `smoke.py:698`) → `healthy` with that
  detail as evidence: an app cluster with no data layer is not a fault, and today's code treats it the
  same way.
- `bin/k3dm-hermes`: import and registration.
- `scripts/lib/hermes/pager.py`: `WEBHOOK_SENSORS = ("eso", "data_layer")`.
- `scripts/lib/hermes/repairs.py`: `_unknown_webhook` and `_r2_precondition` use `data_layer`;
  `_evidence` r1 → `("eso", "data_layer")`, r2 → `("reachability", "data_layer")`.
- `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`: `target_scopes` key
  `"data_layer": "shopping-cart-data"` in place of `"node_pressure": "node"`.
- `docs/guides/hermes.md` (§ sensor 4 and the paging table) and `docs/guides/grafana-dashboards.md:237`:
  rename, and describe what it now measures.
- Tests: `scripts/tests/hermes/test_hermes.py`, `test_pager.py`, `test_repairs.py` (update existing
  `node_pressure` references plus the new tests below).
- `CHANGELOG.md` (one `### Changed` bullet naming the rename, since dashboards and alerts show the sensor
  name), `memory-bank/activeContext.md`, `memory-bank/progress.md`, this doc (Status → FIXED with SHA).

**Tests (offline):**
1. Webhook payload with `Frontend` and `Hub ESO ExternalSecrets` failing and `Data layer` ok →
   `data_layer` healthy, even after 3 cycles.
2. `Data layer` failing → healthy on cycles 1–2, degraded on cycle 3 (today's `threshold=2`
   semantics; say so in the test name). Evidence starts `data layer:`.
3. Webhook unreachable → `unknown` with "source unavailable", and `repairs._unknown_webhook` is still
   true when `eso` is also unknown (R1 path unchanged).
4. No `Data layer` entry → `unknown`; `Data layer` with `ok: None` ("not deployed") → `healthy`.
5. R2: one failing port-forward host, `Data layer` ok, **and an unrelated ESO failure** in the
   webhook list → R2 proposed. (This is the case the bug is about.)
6. `pager` webhook-down still needs both `eso` and `data_layer` unknown for 2 cycles.
7. `git grep -n node_pressure -- scripts bin` returns nothing (docs/plans and dated bug docs are history
   and stay as they are).

**Mutations (paste each red run, then green):** restore the "two or more failed services" rule → test 1
red; make R2 read the old aggregate (any failure → not healthy) → test 5 red; drop the absent-entry check
→ test 4 red.

**Gates (paste output):** `make test-pytest`; `python3 scripts/check-doc-links.py`; `git diff --stat`
lists only the files above.

**Lessons from earlier reviews (2026-09-29/30):** test with realistic inputs, not only minimal
fixtures; cover every numbered test above, or say explicitly which one you skipped and why.

**Do not change:** R3–R8, `approve()`, the correlator, `docs/plans/*`, dated bug docs, `scripts/lib/foundation/`.
Persisted Hermes state keyed by the old name (`debounce.node_pressure`) is simply abandoned; do not
write a migration.

**Commit and hand back:** one commit on `k3d-manager-v1.40.0`, message
`fix(hermes): rename node_pressure to data_layer and stop it double-counting other sensors`.
No PR, no merge, no force-push, no `--no-verify`.

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
