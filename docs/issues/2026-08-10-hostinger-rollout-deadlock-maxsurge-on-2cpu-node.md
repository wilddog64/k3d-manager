# Hostinger rollout deadlock — `maxSurge=1` on a saturated 2-CPU node

**Date:** 2026-08-10
**Cluster:** `ubuntu-hostinger` (single node, 2 CPU)
**Namespace:** `shopping-cart-apps`
**Trigger:** Investigating `ready_pod_digest_mismatch` "failed" rows on the CVE remediation Grafana table.

---

## Two findings (the dashboard rows were a red herring)

### 1. The `ready_pod_digest_mismatch` failures are stale false-positives — RESOLVED

All "failed" rows carry reason `ready_pod_digest_mismatch` — the multi-arch containerd
index-digest aliasing false-negative (verifier compared the pod's *runtime imageID*, an OCI index
digest wrapping the same platform child, against the deploy-pinned spec digest). Fixed by
`33b45a41` ("verify remediation via deployment-pinned digest, not pod imageID"), shipped in v1.23.0
and deployed live 2026-08-09.

Event timeline proves the fix works — same service (`payment`), no image change, flips across the
fix window:

```
2026-08-09T03:06  payment          failed   ready_pod_digest_mismatch   (pre-fix)
2026-08-09T06:26  payment          failed   ready_pod_digest_mismatch   (pre-fix)
2026-08-09T15:58  payment          applied  verified_synced_healthy     (fix live)
2026-08-10T00:19  payment          applied  verified_synced_healthy
```

Every event after ~15:58 on 08-09 is `applied`. The Grafana table is an event **log**, so old failed
rows persist by design — they are not current state. The `order` failures (all 2026-08-06) predate the
fix and order simply hasn't re-remediated since. **No action.**

### 2. Real live problem: order + basket wedged mid-rollout on CPU — FIXED (stopgap)

While verifying, found `order-service` and `basket-service` **stuck mid-rollout**:

- Each deployment is `replicas=1, maxSurge=1, maxUnavailable=0` (the k8s default). A rolling update
  creates the **new** pod *before* removing the old → needs **2× the CPU request** transiently.
- Node was at **cpu requests 1910m / 2000m (95%)** — ~90m free. The surge pods (100m each) could
  never schedule: `FailedScheduling — Insufficient cpu` for **11h** (order, x147) / **26h** (basket).
- Both deployments still reported `1/1` because the **old** replicaset kept serving the old image.

**Consequence:** even with the CVE verifier fixed, order/basket can never *converge* on a patched
image while the node is CPU-saturated — the new pod can't schedule. Capacity silently blocks the CVE
remediation loop for any surge-strategy rollout.

---

## Stopgap applied (2026-08-10)

Live-patched `order-service` + `basket-service` rollout strategy to `maxSurge=0, maxUnavailable=1`
(delete-old-then-create-new — reuses the freed slot instead of needing 2× capacity):

```bash
kubectl --context ubuntu-hostinger -n shopping-cart-apps patch deploy order-service --type=merge \
  -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}}}'
# same for basket-service
```

**Result:** both rollouts completed — order now on `sha-564ccfd24c…` (ready), basket on
`sha-cc6d4e1f5f…` (ready), zero Pending pods, node CPU net-neutral at 95% (old retired as new took
its slot). Cost: a brief single-replica blip during the swap (acceptable for these dev/demo apps).

---

## Durable fix (deferred to v1.25.0 workstream G — hostinger capacity)

The stopgap is a **live patch**: ArgoCD `selfHeal` may revert `strategy` back to the default
`maxSurge=1` (the strategy field is likely absent from the git source), which re-arms the deadlock on
the **next** image bump. The current rollout already completed, so reversion causes no immediate harm,
but the recurrence must be closed durably. Options:

1. **Commit `maxSurge=0, maxUnavailable=1` into the app manifests in git** (the ArgoCD source —
   ArgoCD app `ubuntu-hostinger-shopping-cart-<svc>`, `path: apps/`). Cleanest for single-replica dev
   apps; makes the delete-then-create strategy authoritative and ArgoCD-friendly. **Recommended.**
2. **Bump the hostinger node CPU** (2 → 4) so surge pods fit — the real fix if multi-replica / true
   rolling availability is ever wanted. Heavier; right-sizing requests is the stopgap, node bump is
   the durable path.

Either way this belongs to **v1.25.0-G** (Stripe/Go live acceptance + hostinger capacity), where the
capacity decision already lives.

---

## Related

- `reference_containerd_index_digest_aliasing_verifier` — the false-positive reason string.
- Task #23 (`33b45a41`) — the verifier fix that resolved finding #1.
- v1.25.0 workstream G — hostinger capacity expansion (durable fix for finding #2).
