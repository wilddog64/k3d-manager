# `_vcluster_wait_ready` races vCluster pod creation → `no matching resources found`

**Filed:** 2026-08-16
**Component:** `scripts/plugins/vcluster.sh` — `_vcluster_wait_ready()` (line ~230-237)
**Severity:** high (intermittent blocker for a green Tier 1 e2e smoke; flaky by timing)
**Found by:** live smoke run #8 — the arm64 image fix held (no `ImagePullBackOff`), but the harness
failed one step earlier, at vCluster readiness.

## Problem

Immediately after `vcluster create` reports "Successfully created", the readiness wait fails:

```
kubectl -n vclusters wait --for=condition=Ready --timeout=300s pod -l app=vcluster,release=<name>
error: no matching resources found
kubectl command failed (1)
ERROR: failed to execute ... wait --for=condition=Ready ...: 1
```

The harness then tears the vCluster down and exits 1.

## Root cause

`kubectl wait` returns `no matching resources found` and exits 1 **immediately** when *zero* objects
match the label selector at invocation time — it does **not** block waiting for matching objects to
appear. `vcluster create --connect=false` returns as soon as the StatefulSet is created, but the pod
object is not yet registered in the API server. So the sequence is a race:

1. `vcluster create` → "done"
2. `_vcluster_wait_ready` fires `kubectl wait -l app=vcluster,release=<name>`
3. StatefulSet pod not yet visible → `kubectl wait` finds 0 pods → exits 1 → harness aborts.

The selector `app=vcluster,release=${name}` is **correct** — smoke #7 matched a Ready pod with the exact
same selector and proceeded all the way to the Playwright Job. This is purely a "wait-for-existence"
gap: nothing guarantees at least one pod exists before the condition wait runs.

## Fix

Add a bounded poll-until-pod-exists guard **before** the condition wait, mirroring the existing house
idiom `_wait_for_port_forward` in `scripts/lib/test.sh` (local `timeout`/`interval`/`elapsed`, `until`
loop, `_err` on timeout). Use `_kubectl --no-exit --quiet` so a transient non-match does not abort:

```bash
function _vcluster_wait_ready() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "vCluster name required"
  fi
  local selector="app=vcluster,release=${name}"
  local timeout=60
  local interval=2
  local elapsed=0
  until _kubectl --no-exit --quiet -- -n "$VCLUSTER_NAMESPACE" \
    get pod -l "$selector" --no-headers 2>/dev/null | grep -q .; do
    sleep "$interval"
    elapsed=$((elapsed + interval))
    if (( elapsed >= timeout )); then
      _err "vCluster pod for '${name}' never appeared (selector: ${selector})"
    fi
  done
  _kubectl -n "$VCLUSTER_NAMESPACE" wait --for=condition=Ready --timeout=300s pod -l "$selector"
}
```

The condition wait keeps its own 300s Ready timeout for the scheduling/boot phase; the new guard only
closes the create→register race (60s ceiling is generous — the pod object appears within a few seconds).

## Verification

1. Re-run `./scripts/k3d-manager e2e_verify_vcluster` — readiness passes deterministically; the harness
   proceeds to substrate rollouts → seed → Playwright Job (which now finds the arm64 image locally).
2. The `e2e-run-...` Job reaches `Completed` and the harness writes a pass/fail JSON summary to
   `~/.k3dm/e2e/<run_id>.json`. This is the run that must go green.

## What NOT to do

- Do NOT change the selector — it is correct.
- Do NOT drop the `--for=condition=Ready` wait; the existence poll and the readiness wait cover different
  phases (object registration vs. pod Ready).
- Do NOT add `sleep`-only "settling" delays in place of the poll — poll the actual condition.
