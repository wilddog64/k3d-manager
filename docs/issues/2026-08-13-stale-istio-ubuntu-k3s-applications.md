# Stale Istio `ubuntu-k3s` Applications stuck Unknown

## Diagnosis

The four stale Istio Applications (`istio-base`, `istio-cni`, `istiod`, and
`ztunnel` with the `ubuntu-k3s` suffix) had deletion timestamps from 2026-07-22
and remained in `Unknown` because their ArgoCD cluster registration pointed at
the retired `https://host.k3d.internal:6443` endpoint. ArgoCD reported DNS
failure while loading live state; this was not an Istio workload health issue.

The live `istio-ambient` ApplicationSet already rendered
`destination.name: ubuntu-hostinger`, and the Hostinger Istio applications were
`Synced/Healthy`.

## Remediation

Removed the deletion finalizers from only those four deletion-marked stale
Applications. ArgoCD then deleted them; no Hostinger resources were changed.

## Verification

```text
istio-cni-ubuntu-hostinger   Synced   Healthy
istiod-ubuntu-hostinger      Synced   Healthy
istio-base-ubuntu-k3s        NotFound
istio-cni-ubuntu-k3s         NotFound
istiod-ubuntu-k3s            NotFound
```

No source change is required: the ApplicationSet already targets the active
Hostinger cluster. This issue records the live cleanup and the retired-cluster
failure mode for future reconciliation work.
