# Issue: Istio IngressClass missing on M2 Air infra cluster

**Date:** 2026-03-13
**Component:** `scripts/plugins/cert_manager.sh` / Cluster Setup

## Description

During the Gemini verification of the `deploy_cert_manager` plugin on the M2 Air infra cluster (`k3d-k3d-cluster`), Step 2 of the verification plan failed. The `istio` IngressClass was expected to exist but was not found.

## Evidence

Running the following command on `m2-air.local`:

```bash
kubectl get ingressclass istio
```

Result:
```
Error from server (NotFound): ingressclasses.networking.k8s.io "istio" not found
```

Listing all IngressClasses:
```bash
kubectl get ingressclass
```

Result:
```
No resources found
```

## Impact

The `deploy_cert_manager` plugin depends on the `istio` IngressClass to configure ACME HTTP-01 challenges via Istio. Without this IngressClass, the deployment or subsequent certificate issuance will fail.

## Recommendation

Verify the Istio installation on the infra cluster and ensure the `istio` IngressClass is correctly defined. This might require updating the Istio deployment script or manually applying the IngressClass if it was omitted.
