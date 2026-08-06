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

## Dashboard deployment note

The source dashboard change is pushed in `eae0d607`, but `make platform-ops`
could not apply it because the local Hub API tunnel is unavailable:

```text
error validating "STDIN": error validating data: failed to download openapi:
Get "https://127.0.0.1:57780/openapi/v2?timeout=32s": dial tcp
127.0.0.1:57780: connect: operation not permitted
```

## Recovery

After refreshing the Hostinger access layer, the three Applications were
verified `Synced Healthy` with no Pending pods. The payment rollout also
exposed a missing `payment-db-credentials` Secret; it was recreated from the
already-synchronized Postgres payment-admin and RabbitMQ credentials, and the
unnecessary restart was rolled back. The capacity limitation remains for
future surge rollouts.
