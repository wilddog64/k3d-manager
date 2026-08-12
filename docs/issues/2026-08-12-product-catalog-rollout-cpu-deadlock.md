# Product-catalog rollout blocked by Hostinger CPU capacity

## Symptom

ArgoCD Application `ubuntu-hostinger-shopping-cart-product-catalog` reported `Degraded` while
the service's existing pod remained available.

## Evidence

```text
Deployment: 1 desired | 1 updated | 2 total | 1 available | 1 unavailable
Condition: Progressing=False, ProgressDeadlineExceeded
Event: 0/1 nodes are available: 1 Insufficient cpu
Strategy: maxUnavailable=0, maxSurge=1
```

The rollout created a replacement ReplicaSet, but the single Hostinger node could not schedule the
surge pod alongside the old pod. ArgoCD therefore retried synchronization and marked the Deployment
failed even though one old replica was still serving.

## Fix

The product-catalog overlay now sets `maxSurge: 0` and `maxUnavailable: 1`. This keeps the rollout
within the node's CPU budget by terminating the old pod before scheduling its replacement. It may
produce a brief availability gap; increasing node CPU is the zero-downtime alternative.

## Verification

Render the overlay with `kubectl kustomize services/shopping-cart-product-catalog/` and confirm the
Deployment strategy contains the two values above. After ArgoCD sync, verify the new ReplicaSet reaches
Ready and the Application returns `Synced / Healthy`.
