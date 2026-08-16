# e2e vCluster harness races substrate apply before the vCluster API is serving

**Filed:** 2026-08-16
**Component:** `scripts/plugins/e2e.sh` (Tier 1 vCluster harness, `e2e_verify_vcluster`)
**Severity:** medium (harness robustness — first live end-to-end run failed here; the e2e image
itself was never exercised)

## Problem

The first end-to-end run of `./scripts/k3d-manager e2e_verify_vcluster` (against the freshly
published `ghcr.io/wilddog64/shopping-cart-e2e-tests:latest`) failed at substrate deploy — **not**
because of the e2e image or the substrate content, but because the harness applies the substrate
before the ephemeral vCluster's API server is ready to serve.

Observed on an M4 Air (k3d host cluster, OrbStack). The vCluster control plane (`vcluster-pro:0.32.1`)
took **~7 minutes** to pass its own `/readyz` (the `syncer` container restarted once, Exit 1, and its
startup/readiness/liveness probes to `:8443` were `connection refused` → `context deadline exceeded`
for several minutes). Host-node pressure was **not** the cause — k3d nodes sat at 13–22% CPU /
10–36% memory throughout.

Meanwhile the harness had already moved on. Sequence in `e2e_verify_vcluster` (lines 51–52):

```bash
vcluster_create "$name"                 # returns when the pod is SCHEDULED, not API-ready
_e2e_deploy_substrate "$kubeconfig" …   # first kubectl call hits the vCluster API immediately
```

`vcluster create` logs `pod/<name>-0 condition met` and returns, but that is pod scheduling, **not**
API readiness. `_e2e_deploy_substrate` → `_e2e_provision_pull_secret` → `_e2e_kc … apply` then talks
to the vCluster API at `https://127.0.0.1:10411` and fails:

```
error: failed to download openapi: Get "https://127.0.0.1:10411/openapi/v2?timeout=32s":
  net/http: TLS handshake timeout
ERROR: failed to execute kubectl apply -f -: 1
...
Unable to connect to the server: net/http: TLS handshake timeout
kubectl … patch serviceaccount default … imagePullSecrets … : 1
```

There is **no retry and no readiness gate**: the first TLS timeout fails the apply hard, and the run
never recovers even though the vCluster became `1/1 Ready` a couple of minutes later. No summary JSON
is written because the run wedges before `_e2e_run_job` / `_e2e_write_summary`.

## Root cause

Missing readiness gate between `vcluster_create` (line 51) and `_e2e_deploy_substrate` (line 52).
`vcluster_create` does not (and should not) block on full API readiness; the e2e harness must gate on
it itself before issuing substrate `kubectl` calls, because ephemeral vCluster control-plane startup
on a laptop can legitimately take several minutes.

## Fix

Add `_e2e_wait_vcluster_ready` and call it after `vcluster_create`, before `_e2e_deploy_substrate`:

1. New env default near the other `E2E_*` vars (top of `e2e.sh`):
   ```bash
   E2E_VCLUSTER_READY_TIMEOUT="${E2E_VCLUSTER_READY_TIMEOUT:-600}"
   ```
   (10 min — the observed cold start was ~7 min; leave headroom. Poll interval 5s.)

2. New helper (poll the vCluster API's `/readyz` through the same `_e2e_kc` wrapper the rest of the
   harness uses, so it goes through the correct kubeconfig/context):
   ```bash
   function _e2e_wait_vcluster_ready() {
     local kubeconfig="${1:-}"
     [[ -z "$kubeconfig" ]] && _err "e2e: _e2e_wait_vcluster_ready requires a kubeconfig"
     local deadline=$(( $(date +%s) + E2E_VCLUSTER_READY_TIMEOUT ))
     _info "[e2e] Waiting for vCluster API to be ready (timeout ${E2E_VCLUSTER_READY_TIMEOUT}s)"
     while (( $(date +%s) < deadline )); do
       if _e2e_kc "$kubeconfig" get --raw='/readyz' >/dev/null 2>&1; then
         _info "[e2e] vCluster API is ready"
         return 0
       fi
       sleep 5
     done
     _err "e2e: vCluster API not ready within ${E2E_VCLUSTER_READY_TIMEOUT}s"
   }
   ```

3. Wire it in `e2e_verify_vcluster` between the two existing lines:
   ```bash
   vcluster_create "$name"
   _e2e_wait_vcluster_ready "$kubeconfig"
   _e2e_deploy_substrate "$kubeconfig" "$candidate_digest"
   ```

Rationale for `/readyz` over `get nodes`: it is the API server's own readiness endpoint, returns fast
once the control plane is serving, and needs no RBAC. Route it through `_e2e_kc` so it uses the
vCluster kubeconfig exactly as the substrate calls do (same TLS path that was timing out).

## Secondary (optional, smaller)

Even with the gate, a transient blip mid-apply would still fail hard. Low-effort hardening: wrap the
first substrate `kubectl apply` (line 74) in a short bounded retry (e.g. 3× with 5s backoff). Not
required if the readiness gate lands — file only if a retry is wanted for defence in depth.

## Verification

1. `bash -n scripts/plugins/e2e.sh` — syntax clean.
2. `shellcheck -S warning scripts/plugins/e2e.sh` — no new findings vs. parent.
3. BATS (extend the e2e suite, pure-logic): assert `e2e_verify_vcluster` calls
   `_e2e_wait_vcluster_ready` **before** `_e2e_deploy_substrate` (ordering guard), and that the helper
   references `/readyz` and honours `E2E_VCLUSTER_READY_TIMEOUT`.
4. **Live (Claude-owned):** re-run `./scripts/k3d-manager e2e_verify_vcluster`; the harness must wait
   out the ~7-min vCluster start, then apply the substrate and run the Playwright Job to a JSON
   summary. This is the run that failed today.

## What NOT to do

- Do NOT make `vcluster_create` itself block on API readiness — keep the gate in the e2e harness so
  other vCluster callers are unaffected.
- Do NOT drop `--validate` / add `--validate=false` to dodge the openapi fetch — that masks the race
  rather than fixing it.
- Do NOT lower probe timeouts or touch the vCluster chart — the control plane was healthy, just slow.
- Do NOT create a PR; do NOT commit to `main`. Commit to `k3d-manager-v1.25.0`.
