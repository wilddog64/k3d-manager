# Issue: `test_eso` failure — `ClusterSecretStore` API version mismatch

## Date
2026-02-27

## Environment
- Hostname: `m4-air.local`
- OS: Darwin (macOS)
- Cluster Provider: `orbstack`
- ESO Version: (unknown, but CRDs are `v1`)

## Symptoms
`test_eso` fails when creating the `ClusterSecretStore`:

```
error: resource mapping not found for name: "vault-store-1772153268-28478" namespace: "" from "STDIN": no matches for kind "ClusterSecretStore" in version "external-secrets.io/v1beta1"
ensure CRDs are installed first
kubectl command failed (1): kubectl apply -f - 
ERROR: failed to execute kubectl apply -f -: 1
```

## Root Cause
The `scripts/lib/test.sh` script defines `ClusterSecretStore` using `apiVersion: external-secrets.io/v1beta1`. However, the installed External Secrets Operator on the `m4-air` cluster expects `apiVersion: external-secrets.io/v1`.

## Resolution
**FIXED (2026-02-27)** — Updated `scripts/lib/test.sh` line 591: `external-secrets.io/v1beta1` → `external-secrets.io/v1` for `ClusterSecretStore`. `ExternalSecret` on line 611 was already using `v1`.

## Evidence
`kubectl explain clustersecretstore` output:
```
GROUP:      external-secrets.io
KIND:       ClusterSecretStore
VERSION:    v1
```

`scripts/lib/test.sh` (lines 591-593):
```bash
  cat <<EOF | _kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
```
