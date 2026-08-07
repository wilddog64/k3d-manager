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

The payment Secret is owned by the existing data-layer `postgres-payment-app`
ExternalSecret (`SecretSynced=True`). A temporary duplicate service-level
ExternalSecret was rejected by ESO and removed; it was not kept in GitOps.

## Request-right-sizing investigation (2026-08-07)

Request reduction is technically applicable, but requires service-level
changes and load validation. The node reports only 411m actual CPU usage (20%)
while pod requests reserve 1,910m of its 2 CPU allocatable capacity. The
pending order, product-catalog, and payment surge pods request 100m, 100m, and
200m respectively. Their replacement pods are blocked by scheduling requests,
not observed CPU consumption.

The safe candidate is a staged reduction of over-reserved non-critical service
requests (starting with one service, preserving limits), followed by a
zero-downtime rollout and peak-load check. Do not reduce all requests based on
the single low-usage sample: Java startup and traffic spikes need headroom, and
reducing requests weakens scheduling guarantees. Capacity expansion remains the
permanent fix; right-sizing is a short-term mitigation that needs a separate
spec across the affected service repositories.

## Bounded peak-load validation (2026-08-07)

An ephemeral `curlimages/curl:8.10.1` pod issued 300 liveness requests to the
internal order service (10 concurrent loops, 10m CPU request). All responses
were HTTP 200. Node usage rose from 411m to 618m (20% to 30%), the order
Deployment remained `1/1` ready, and order, payment, and product-catalog
Applications remained `Synced Healthy`. The probe pod was deleted afterward.

This validates the right-sized requests under a bounded liveness burst; it is
not a sustained production traffic or application-checkout benchmark.
