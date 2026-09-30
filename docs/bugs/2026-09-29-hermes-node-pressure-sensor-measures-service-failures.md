# Bug: Hermes `node_pressure` measures webhook service failures, not node pressure

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-29 by Claude (cloud session), from the operator's Hermes Status dashboard
**Status:** FIXED — option (b) implemented 2026-09-30; commit SHA recorded in the completion handoff.
**Severity:** Medium — misleading on the dashboard, double-counts other sensors, and blocks self-repair R2
**Component:** `scripts/lib/hermes/sensors.py` (`node_pressure`), `scripts/lib/hermes/repairs.py`

## Codex brief

**Goal:** `node_pressure` measures real node health, read straight from the clusters. A new
`data_layer` sensor takes over the webhook's `Data layer` check. Service failures that belong to
other sensors no longer degrade either one, so R2 is no longer blocked by them.

**Runs where:** Codex web is fine. Pure Python and docs; all tests are offline with a stubbed runner.

**Decision:** option (b), chosen by the operator on 2026-09-30. Keep the name `node_pressure`, make it
real, and add `data_layer`. Because `node_pressure` stops reading the webhook, the webhook-down signal
(the pager's `WEBHOOK_SENSORS` and `repairs._unknown_webhook`) moves to `eso` + `data_layer`.

**Files to touch (only these):**
- `scripts/lib/hermes/sensors.py`:
  - **`node_pressure(run, state, contexts=None, threshold=2)`**: for each context in `contexts`
    (default: env `K3DM_HERMES_NODE_CONTEXTS`, comma-separated, else `k3d-k3d-cluster,ubuntu-hostinger`)
    run `["kubectl", "--context", ctx, "get", "nodes", "-o", "json", "--request-timeout=10s"]` through the
    injected runner (as `kine` does). Parse the JSON from stdout; never pass it as an argument anywhere.
    A node is a problem when `Ready` is not `True`, or when `MemoryPressure`, `DiskPressure` or
    `PIDPressure` is `True`. Status:
    - **degraded** (debounced with `_debounced("node_pressure", …, threshold, state)`, today's semantics)
      when any readable context has a problem node. Evidence: `"<ctx>/<node> <Condition>"`, first 3,
      `; `-joined.
    - **healthy** when every readable context is clean. If some contexts were unreadable, still healthy,
      but append `"; unreadable: <ctx,…>"` to the evidence.
    - **unknown** ("node status source unavailable") only when **no** context was readable.
    - `data = {"problems": [{"context","node","condition"}...], "unreadable": [ctx...]}`.
  - **`data_layer(fetch, state, provider="", token=None, threshold=2)`**: new. It takes over today's
    webhook-payload logic, narrowed. `_unavailable("data_layer", WEBHOOK_SERVICE)` without a token;
    `unknown` "data layer status source unavailable" on fetch failure or an all-`None` payload.
    Degrade (debounced) **only** when the `Data layer` entry has `ok is False`, with evidence
    `data layer: <detail>`. `ok is None` ("not deployed (namespace shopping-cart-data absent …)",
    `smoke.py:698`) → `healthy` with that detail. No `Data layer` entry → `unknown` ("data layer check
    absent from webhook payload"). Other failing services never affect it.
- `bin/k3dm-hermes`: `node_pressure(_probe_run, state)`, `data_layer(webhook_fetch, state, token=webhook)`,
  and the imports.
- `scripts/lib/hermes/pager.py`: `WEBHOOK_SENSORS = ("eso", "data_layer")`. `node_pressure` then falls
  under the generic "unknown 30+ min" page. That is intended: Hermes that cannot read any node for
  30 minutes should page.
- `scripts/lib/hermes/repairs.py`: `_unknown_webhook` uses `eso` + `data_layer`. `_r2_precondition`
  requires `node_pressure == "healthy"` **and** `data_layer != "degraded"`. `_evidence`: r1 →
  `("eso", "data_layer")`, r2 → `("reachability", "node_pressure", "data_layer")`.
- `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`: `target_scopes` keeps
  `"node_pressure": "node"` and adds `"data_layer": "shopping-cart-data"`.
- `docs/guides/hermes.md` (sensor list and the paging table) and `docs/guides/grafana-dashboards.md:237`:
  describe both sensors; the webhook-down signature is now `eso` + `data_layer`.
- Tests: `scripts/tests/hermes/test_hermes.py`, `test_pager.py`, `test_repairs.py`.
- `CHANGELOG.md` (`### Changed`: node_pressure now reads node conditions; `### Added`: data_layer),
  `memory-bank/activeContext.md`, `memory-bank/progress.md`, this doc (Status → FIXED with SHA).

**Tests (offline; build node fixtures from real `kubectl get nodes -o json` shape, including a large
`status.images` list, over 100 KB per context, not only minimal dicts):**
1. Webhook list with `Frontend` and `Hub ESO ExternalSecrets` failing, `Data layer` ok, nodes clean →
   `node_pressure` and `data_layer` both healthy, even after 3 cycles.
2. One node `DiskPressure=True` → `node_pressure` healthy on cycles 1–2, degraded on cycle 3; evidence
   `k3d-k3d-cluster/<node> DiskPressure`. One node `Ready=False` → evidence names `NotReady`.
3. The hub readable and `ubuntu-hostinger` unreadable (runner rc≠0) → healthy, with
   `unreadable: ubuntu-hostinger` in evidence and `data.unreadable`. Both unreadable → unknown.
4. `data_layer`: `Data layer` `ok False` → degraded after debounce; `ok None` → healthy; entry absent →
   unknown; fetch error → unknown "source unavailable".
5. R2: one failing port-forward host, nodes clean, `Data layer` ok, **and an unrelated ESO failure**
   → R2 proposed. With `node_pressure` degraded → not proposed.
6. Webhook down (fetch fails): `eso` and `data_layer` unknown → `_unknown_webhook` true and the pager's
   2-cycle webhook-down page still fires. `node_pressure` stays healthy in that case (it doesn't use
   the webhook), and that must not suppress the page.
7. Pager: `node_pressure` unknown for `SENSOR_UNKNOWN_CYCLES` → the generic unknown page fires.

**Mutations (paste each red run, then green):** restore the "two or more failed services" rule in
either sensor → test 1 red; ignore `PIDPressure`/`DiskPressure` → test 2 red; return unknown when *any*
context is unreadable → test 3 red; leave `node_pressure` in `WEBHOOK_SENSORS` → test 6 or 7 red.

**Gates (paste output):** `make test-pytest`; `python3 scripts/check-doc-links.py`; `git diff --stat`
lists only the files above.

**Lessons from earlier reviews (2026-09-29/30):** test with realistic input sizes, not only minimal
fixtures; never pass cluster JSON as a command-line argument; cover every numbered test above, or say
explicitly which one you skipped and why.

**Do not change:** R1's command, R3–R8, `approve()`, the correlator, `hostnet_drift`, `docs/plans/*`,
dated bug docs, `scripts/lib/foundation/`. Persisted debounce state is not migrated.

**Commit and hand back:** one commit on `k3d-manager-v1.40.0`, message
`fix(hermes): make node_pressure read node conditions and split out a data_layer sensor`.
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

## Fix — options (operator chose (b) on 2026-09-30)

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
