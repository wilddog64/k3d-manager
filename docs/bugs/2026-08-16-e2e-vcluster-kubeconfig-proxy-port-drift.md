# e2e vCluster kubeconfig port drifts — background-proxy port is not durable

**Filed:** 2026-08-16
**Component:** `scripts/plugins/vcluster.sh` (`_vcluster_export_kubeconfig`), consumed by
`scripts/plugins/e2e.sh` (Tier 1 harness, all `_e2e_kc` calls)
**Severity:** high (blocks a green live e2e smoke; readiness gate alone cannot fix it)
**Found by:** the live re-run of `e2e_verify_vcluster` after the readiness-gate fix landed
(`docs/bugs/2026-08-16-e2e-vcluster-api-readiness-race.md`, commit `38abfab5`). The gate fired
correctly ("Waiting for vCluster API to be ready") but the run still exited 1 — this is a **separate,
deeper** connectivity defect the gate exposed.

## Problem

`vcluster` on this host is **0.36.1** (memory-bank said 0.32.1 — stale). 0.36.x connects via a
**background-proxy docker container** (default `--background-proxy=true`,
`ghcr.io/loft-sh/vcluster-pro:0.36.1`), NOT an in-process `kubectl port-forward`. That proxy container
publishes the vCluster API (`8443/tcp`) on a **random host port**:

```
docker port vcluster_<name>_vclusters_k3d-k3d-cluster_background_proxy
  8443/tcp -> 0.0.0.0:12707
```

`_vcluster_export_kubeconfig` (vcluster.sh:246) captures the kubeconfig **once**, at create time, via
`vcluster connect <name> -n <ns> --print`. That kubeconfig hard-codes the host port that was current at
that instant:

```
server: https://127.0.0.1:12128     # written at create time
```

**The two ports do not stay in sync.** Every fresh `vcluster connect --print` allocates a *new* random
local port and re-creates the proxy container on it (observed: 12128 → 12707). Critically, when the
**syncer pod restarts** (RESTARTS 1 was observed this run — the bug-race spec already documented the
~7-min cold start with one syncer restart), the proxy container is recreated and the published host port
**drifts**. From that moment the create-time kubeconfig (`:12128`) points at a dead port and every
`_e2e_kc` call fails:

```
KUBECONFIG=<create-time kubeconfig> kubectl get --raw=/readyz
  Unable to connect to the server: EOF
```

So `_e2e_wait_vcluster_ready` polls `/readyz` through a kubeconfig whose port has drifted out from under
it and can never succeed; and even if readiness is caught in the brief pre-restart window, the substrate
apply later fails the same way when the port drifts mid-run. The harness has **no durable connection** to
the ephemeral vCluster.

## Root cause

`vcluster connect --print` yields a **point-in-time** kubeconfig bound to a **non-deterministic,
non-durable** local port owned by a background-proxy container that is re-created (with a new port) on
syncer pod restart. The harness assumes the create-time kubeconfig stays valid for the whole run; under
0.36.x's background-proxy model it does not.

## Fix (options, prefer 1)

**Option 1 — pin a deterministic local port (smallest change, keeps the proxy model).**
Pass `--local-port` to the connect call in `_vcluster_export_kubeconfig` so the kubeconfig port is fixed
and survives proxy re-creation (a recreated proxy republishes the same fixed port):

```bash
# vcluster.sh: _vcluster_export_kubeconfig
config="$(_run_command -- vcluster connect "$name" -n "$VCLUSTER_NAMESPACE" \
  --local-port "${VCLUSTER_LOCAL_PORT:-11443}" --print)"
```

- New env `VCLUSTER_LOCAL_PORT` (default e.g. 11443) near the other `VCLUSTER_*` vars.
- The e2e harness runs **one** vCluster at a time (serialize-live-sandbox rule), so a fixed port does not
  collide. If concurrency is ever needed, derive the port from the run id.
- Verify: after a forced syncer restart, `docker port <proxy>` still shows `-> 11443` and the
  create-time kubeconfig still reaches `/readyz`.

**Option 2 — disable the background proxy, manage our own port-forward.**
`--background-proxy=false` makes `connect` a foreground `kubectl port-forward`; the harness would have to
launch it detached, pin `--local-port`, health-check it, and tear it down in `_e2e_teardown`. More moving
parts; only pursue if Option 1's proxy proves flaky across restarts.

**Option 3 — re-derive the kubeconfig lazily.** Re-run `vcluster connect --print` (capturing the current
port) immediately before each phase. Fragile (racy against ongoing restarts) — not recommended.

## UPDATE 2026-08-16 (live-verified): port-pin is NECESSARY but NOT SUFFICIENT

Landed Option 1 (`--local-port 11443`, commit `1f1f98ce`) and re-ran the live smoke. The kubeconfig
port now stays fixed and the proxy republishes `11443->8443` even across the syncer restart — but the
smoke **still exited 1**, aborting in the readiness gate. Direct diagnosis on the live vCluster
(`e2e-1786918166-24149`) established the true mechanism:

- vcluster 0.36.x's background-proxy container runs an **internal `kubectl port-forward`**
  (`docker logs …_background_proxy` → a single `Forwarding from 0.0.0.0:8443 -> 8443` line).
- On the syncer pod's startup restart (RESTARTS 1), that port-forward's backend pod dies and
  **`kubectl port-forward` does not reconnect**. The proxy keeps LISTENing on 11443 but every request
  gets `EOF` / `connection reset by peer` / `TLS handshake timeout`.
- A plain `vcluster connect --print` re-run **reuses the wedged proxy container** and still fails.
- **Recreating the proxy fixes it:** `docker rm -f <…_background_proxy>` then `vcluster connect
  --local-port 11443 --print` establishes a live port-forward to the *current* pod. Because the port
  is pinned and the CA is unchanged, the **original create-time kubeconfig then returns `/readyz` →
  `ok`** and lists namespaces. (Verified: after proxy recreation the create-time kubeconfig succeeded
  on the first probe.)

**Refined fix = Option 1 (port pin, done) + make the readiness gate refresh the proxy.** The gate
must, on each failed `/readyz` probe, recreate the background-proxy (remove the stale container +
reconnect on the pinned port) before retrying. With the port fixed, the create-time kubeconfig the gate
already holds becomes valid again the moment a healthy proxy is republished — no kubeconfig rewrite
needed. New helper `_vcluster_refresh_connection <name>` in vcluster.sh owns the docker-proxy
recreation; `_e2e_wait_vcluster_ready` gains the vCluster name and calls it between probes
(interval `E2E_VCLUSTER_READY_INTERVAL`, default 10s). This is docker-scoped, which is correct — the
Tier 1 substrate is the k3d hub and the background-proxy IS a docker container.

## UPDATE 2026-08-16 (2nd live re-run): a distinct SECOND failure mode — syncer crash-loop from datastore starvation

The 2nd smoke (with port-pin + proxy-refresh) still timed out, but for a **different** reason than the
proxy. The ephemeral vCluster syncer was **crash-looping** (RESTARTS 12, 0/1). Syncer logs showed the
real cause — NOT clock skew (host vs OrbStack VM epoch differed by only ~14s; the `23:34` vs `16:34` is
just UTC-vs-PDT display):

```
Slow SQL ... total time: 2.301s        (kine datastore — I/O starved)
leaderelection lost                     (controller-manager can't renew its lease in time)
error running controller-manager: ... exit status 1
running interrupt handlers              (syncer process exits -> pod restarts -> repeat)
```

So under hub I/O pressure the vCluster's kine datastore is slow → controller-manager loses leader
election → the syncer exits → pod restarts, indefinitely. A crash-looping API server defeats ANY
connection logic. Two contributing factors, both addressed:

1. **Harness self-load.** The first cut refreshed the proxy on *every* failed probe (~every 10s ⇒ ~60
   `docker rm` + `vcluster connect` cycles across the 600s timeout), hammering a still-starting syncer.
   Fixed: decouple probe cadence (`E2E_VCLUSTER_READY_INTERVAL`, default 5s) from refresh cadence
   (`E2E_VCLUSTER_READY_REFRESH_INTERVAL`, default 30s) so the gate probes often but recreates the proxy
   rarely.
2. **Hub headroom.** Tier 1 e2e needs enough disk-I/O headroom for the ephemeral control plane's kine
   datastore. Run 1 (RESTARTS 1) succeeded; run 2 hit contention from an orphaned crash-looping vCluster
   (teardown had not run — the EXIT trap issue) plus accumulated churn. Post-teardown node pressure was
   fine (CPU 12–25%, mem 5–38%, host 37% free), confirming the pressure was self-inflicted, not a
   baseline shortage. **Operational rule:** ensure teardown actually runs (no orphaned vClusters), and
   avoid running the smoke while the host is under heavy load. If crash-loops persist on a calm host,
   consider giving the vCluster a non-embedded/faster datastore or bumping its resources in
   `scripts/etc/vcluster/values.yaml`.

## UPDATE 2026-08-16 (datastore fix implemented): memory-backed emptyDir for the ephemeral control plane

Decision (user, 2026-08-16): fix the crash-loop at its source — the slow disk-backed kine datastore.
For a **throwaway** e2e vCluster there is no reason to persist state, so back the control-plane data
directory with a **memory emptyDir (tmpfs)**, eliminating the overlay-FS I/O that starved kine.

Verified the vcluster 0.36.1 chart schema with `helm template loft-sh/vcluster --version 0.36.1`:
`controlPlane.statefulSet.persistence.dataVolume` is the purpose-built override ("Only works correctly
if volumeClaim.enabled=false"). `addVolumes` was wrong — it duplicates the `data` volume and breaks the
pod spec. With `volumeClaim.enabled=false` the control plane renders as a Deployment (no PVC), and
`dataVolume` replaces the default disk `emptyDir: {}` at `/data` with a memory-backed one.

`scripts/etc/vcluster/values.yaml` now:

```yaml
controlPlane:
  statefulSet:
    resources:
      requests: { cpu: 200m, memory: 256Mi }
      limits:   { cpu: "1",  memory: 1Gi }   # bumped: tmpfs counts against the pod mem limit;
                                              # extra CPU also guards leader-election under load
    persistence:
      volumeClaim:
        enabled: false                        # no PVC — ephemeral, Deployment not StatefulSet
      dataVolume:
        - name: data
          emptyDir:
            medium: Memory                    # tmpfs -> kine SQLite I/O is RAM-fast
            sizeLimit: 1Gi
```

Rationale for the resource bump: a `medium: Memory` emptyDir's usage counts against the container
memory limit, so 512Mi was too tight; 1Gi gives the syncer + the (tiny, few-MB) kine DB headroom. CPU
limit 1 core because lost leader election is partly CPU starvation during the slow-SQL spikes.

## Interaction with the readiness gate (keep it)

The readiness gate (`_e2e_wait_vcluster_ready`, commit `38abfab5`) is still correct and necessary — it
handles the legitimate multi-minute API cold start. This fix makes the connection the gate polls
**durable** so the gate can actually observe readiness. Land Option 1, then the gate + the durable port
together should let the substrate apply and the Playwright Job run to a JSON summary.

## Also update

- **memory-bank / this spec:** vcluster is **0.36.1**, not 0.32.1. The connection model is a
  background-proxy docker container, not an in-process port-forward.

## Verification

1. `bash -n scripts/plugins/vcluster.sh`; `shellcheck -S warning scripts/plugins/vcluster.sh` — clean.
2. BATS (pure-logic): `_vcluster_export_kubeconfig` passes `--local-port` and honours
   `VCLUSTER_LOCAL_PORT`; existing vcluster.bats stays green.
3. **Live (Claude-owned):** re-run `e2e_verify_vcluster`; force/observe a syncer restart; confirm the
   create-time kubeconfig still reaches `/readyz` on the pinned port, the substrate applies, and the
   Playwright Job writes a pass/fail JSON summary. This is the run that must go green.

## UPDATE 2026-08-16 (next live run): the port-pin turned a teardown gap into a hard blocker — orphaned background-proxy container holds 11443

The port-pin (Option 1) is correct and stays. But it exposed a **teardown defect** that the old
random-port model masked. Live symptom on the next smoke (`e2e-1786932501-16086`): the proxy could not
start at all —

```
warn  Error exposing local vcluster, will fallback to port-forwarding:
      error starting background proxy: ...
docker: ... Bind for 0.0.0.0:11443 failed: port is already allocated
```

Root cause: a **previous run's** background-proxy container
(`vcluster_e2e-1786931626-18560_..._background_proxy`) was still `Up` and still publishing
`0.0.0.0:11443->8443`. `vcluster_destroy` (vcluster.sh) runs `vcluster delete --wait` and removes the
kubeconfig, but it **never removes the background-proxy docker container**. When `vcluster delete` fails
(observed smoke9: "parent context unreachable / couldn't find vcluster" — the child API is already gone,
so the CLI can't clean itself up), the proxy container is orphaned. Because the port is now **pinned to
11443**, that orphan collides with the *next* run's proxy: the new proxy can't bind, vcluster falls back
to an in-process port-forward, but the canonical `0.0.0.0:11443` is owned by the dead run's proxy →
kubeconfig endpoint is poisoned → the harness wedges before applying substrate (no substrate pods ever
sync). Under the old random-port model an orphan was harmless (next run picked a different port); the pin
makes cleanup mandatory.

This is the concrete second symptom of the already-known broken EXIT-trap/teardown. `_e2e_teardown`
(e2e.sh) does call `vcluster_destroy`, but (a) `vcluster_destroy` doesn't remove the proxy container, and
(b) a hard-failed `vcluster delete` aborts before any cleanup.

### Fix (both in vcluster.sh, minimal)

1. **Extract the proxy-removal already inlined in `_vcluster_refresh_connection` into a helper**
   `_vcluster_remove_proxy <name>` (docker ps `--filter name=vcluster_${name}_ --filter
   name=background_proxy` → `docker rm -f`), and have `_vcluster_refresh_connection` call it (no behaviour
   change there).
2. **`vcluster_destroy` must always remove the proxy container**, even when `vcluster delete` fails:
   make `vcluster delete` non-fatal and fall back to `helm -n "$VCLUSTER_NAMESPACE" uninstall "$name"
   --wait` on failure, then unconditionally call `_vcluster_remove_proxy "$name"` before removing the
   kubeconfig. Removal must be idempotent (`|| true`) so a clean run with no orphan is a no-op.

This keeps teardown correct whether the child API is reachable or not, so 11443 is always freed for the
next run.

### Verification (this symptom)

- After a run (success OR forced failure), `docker ps -a --filter name=background_proxy` shows **none**,
  `helm -n vclusters list` is empty, and `lsof -iTCP:11443 -sTCP:LISTEN` is empty.
- Back-to-back `e2e_verify_vcluster` runs: the 2nd run's proxy binds 11443 cleanly (no "port is already
  allocated"), substrate applies, Playwright Job writes the JSON summary.

### What NOT to do (this symptom)

- Do NOT switch back to a random proxy port to dodge the collision — durability (the pin) is required;
  fix teardown instead.
- Do NOT rely solely on the EXIT trap: a hard-killed harness skips it, so operational cleanup
  (`docker rm -f` the proxy + `helm uninstall` the release) is still the manual recovery lever.

## UPDATE 2026-08-16 (smoke11, teardown-fix landed): proxy-refresh must cover the WHOLE run, not just the readiness gate — plus a teardown context-leak

Two findings from smoke11 (`e2e-1786933762-7641`), after the orphan-proxy teardown fix above landed:

**(A) The substrate fixes are VALIDATED.** With the initContainer + postgres-liveness fixes
(`docs/bugs/2026-08-16-e2e-order-postgres-startup-ordering.md`), the synced pods proved the substrate
came up healthy: `order`, `postgres`, `redis`, `product-catalog`, `basket` all reached `1/1 Running`
(direct `kubectl get pods -n vclusters` on the host, showing the `*-x-shopping-cart-apps-x-<vc>` mirror
pods). `order` reaching Ready confirms the startup-ordering fix works. No substrate defect remains.

**(B) The real remaining blocker: the proxy-refresh is scoped ONLY to the readiness gate.** The refined
fix earlier wired `_vcluster_refresh_connection` into `_e2e_wait_vcluster_ready` alone. But the
background-proxy's internal port-forward can drop at ANY point in the run (a single transient is enough —
it never self-reconnects), including during the substrate-deploy phase. Smoke11 died here:

```
INFO: [e2e] Waiting for rollout: redis
Unable to connect to the server: net/http: TLS handshake timeout
kubectl command failed (1): kubectl -n shopping-cart-apps rollout status deployment/redis --timeout=300s
ERROR: failed to execute ... rollout status deployment/redis --timeout=300s: 1
```

redis was actually `1/1` — the substrate was fine; the `rollout status` call just hit a dropped proxy and
`_e2e_kc` aborted the whole harness. `_e2e_kc` (e2e.sh:37) is `KUBECONFIG=... _run_command -- kubectl`
with **no --no-exit and no retry**, so the first connection blip anywhere past the gate kills the run.

### Fix (e2e.sh `_e2e_kc` — central, covers every vCluster kubectl call)

Make `_e2e_kc` proxy-drop-aware: on a failed kubectl, **probe API reachability** (`kubectl version`,
which contacts the server) to distinguish a dropped proxy from a genuine kubectl failure; if unreachable,
call `_vcluster_refresh_connection "${_E2E_ACTIVE_NAME}"` (recreates the proxy on the pinned 11443 — the
same create-time kubeconfig then works) and retry, up to `E2E_KC_MAX_ATTEMPTS` (default 4) with
`E2E_KC_RETRY_INTERVAL` (default 5s). If the API is reachable, the failure is real → `_err` as today.
This preserves streaming (kubectl runs directly, not captured). This makes proxy-refresh cover the whole
run, so a transient drop during deploy/job-wait self-heals instead of aborting.

- **stdin guard:** skip the retry loop when args contain `-f -` (e.g. `create ... -o yaml | _e2e_kc apply
  -f -`) — a retry can't re-read consumed stdin. Those calls run right after the gate (API just confirmed
  up), so single-shot is safe; behaviour is unchanged from today (still `_err` on failure, no regression).
- The readiness gate keeps its own refresh loop (it runs before `_E2E_ACTIVE_NAME`-based refresh is even
  needed and has its own cadence knobs); this change is additive.

**(C) Teardown context-leak (follow-up, lower priority).** smoke11's teardown showed `vcluster delete`
AND the `helm uninstall` fallback BOTH tried to reach `https://127.0.0.1:11443` (the dead vCluster), not
the hub — the ambient kube context had leaked to the vCluster, so `helm uninstall --wait` hung/failed and
the hub release orphaned (the proxy container WAS removed correctly — the 11443-collision fix works). The
`_vcluster_remove_proxy` step succeeded; only the release-uninstall leaked context. Durable fix: teardown
(`vcluster_destroy`) must pin the **hub** context/kubeconfig explicitly for its `vcluster delete` and
`helm uninstall` calls (e.g. `helm --kube-context <hub>` / `KUBECONFIG=<hub>`), and use `--wait=false`
(or a bounded `--timeout`) on the helm fallback so it never blocks on the dead child API. Manual recovery
meanwhile: `kubectl --context <hub> -n vclusters delete deploy,sts -l release=<name> --wait=false`,
delete the `owner=helm,name=<name>` secret, and force-delete stuck mirror pods `--grace-period=0 --force`.

### Verification (this symptom)

1. `bash -n scripts/plugins/e2e.sh`; `shellcheck -S warning scripts/plugins/e2e.sh` — clean.
2. Live: re-run `e2e_verify_vcluster`; if the proxy drops mid-deploy, the log shows
   `vCluster API unreachable (attempt N/…); refreshing proxy and retrying` and the rollout continues to
   `successfully rolled out` instead of aborting; the run proceeds to the Playwright Job + JSON summary.

## What NOT to do

- Do NOT remove the readiness gate — it fixes a different (cold-start) failure.
- Do NOT retry `_e2e_kc` on EVERY non-zero rc — that masks genuine kubectl failures; gate the retry on an
  API-reachability probe so only proxy drops are retried.
- Do NOT add `--insecure-skip-tls-verify` or `--validate=false` to paper over the EOF.
- Do NOT create a PR; do NOT commit to `main`. Commit to `k3d-manager-v1.25.0`.
