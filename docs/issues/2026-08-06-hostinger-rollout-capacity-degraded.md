# Hostinger rollouts degraded by single-node CPU capacity

## Observation

The ArgoCD Applications `ubuntu-hostinger-shopping-cart-order`,
`ubuntu-hostinger-shopping-cart-payment`, and
`ubuntu-hostinger-shopping-cart-product-catalog` are `Synced` but `Degraded`.
Each Deployment has one ready pod and one replacement pod stuck `Pending`.

## Evidence

```text
0/1 nodes are available: 1 Insufficient cpu. no new claims to deallocate,
preemption: 0/1 nodes are available: 1 No preemption victims found
```

The only Hostinger node (`srv1754834`) has 2 CPU allocatable and 1,910m
requested (95%). The Phase 4 rollout policy intentionally uses
`maxUnavailable: 0` and `maxSurge: 1`, so a replacement pod cannot be
scheduled while the old pod remains ready. This is a capacity constraint, not
an application health failure.

## Required remediation

Resize the Hostinger VPS to provide additional CPU or add a worker node, then
allow the pending surge pods to schedule. Do not change the rollout policy to
permit downtime without an explicit owner decision. The repository's
`k3s-hostinger` provider currently provisions a permanent single-node VPS and
has no supported worker/resize target; infrastructure-panel work is required.

