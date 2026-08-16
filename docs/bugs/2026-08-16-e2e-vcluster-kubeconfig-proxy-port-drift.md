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

## What NOT to do

- Do NOT remove the readiness gate — it fixes a different (cold-start) failure.
- Do NOT add `--insecure-skip-tls-verify` or `--validate=false` to paper over the EOF.
- Do NOT create a PR; do NOT commit to `main`. Commit to `k3d-manager-v1.25.0`.
