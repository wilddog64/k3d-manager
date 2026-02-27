# Issue: `test_eso` failure — `ClusterSecretStore` v1 schema incompatibility

## Date
2026-02-27

## Environment
- Hostname: `m4-air.local`
- OS: Darwin (macOS)
- Cluster Provider: `orbstack`
- ESO Version: (CRDs are `v1`)

## Symptoms
After updating `scripts/lib/test.sh` to use `apiVersion: external-secrets.io/v1`, `test_eso` fails with a schema validation error:

```
Error from server (BadRequest): error when creating "STDIN": ClusterSecretStore in version "v1" cannot be handled as a ClusterSecretStore: strict decoding error: unknown field "spec.provider.vault.tls.insecureSkipVerify"
kubectl command failed (1): kubectl apply -f - 
ERROR: failed to execute kubectl apply -f -: 1
```

## Root Cause
In `external-secrets.io/v1`, the `insecureSkipVerify` field is not present under `spec.provider.vault.tls`. The `tls` object in `v1` is primarily for mutual TLS (client certificates). 

Server-side TLS verification (like ignoring self-signed certs) is typically handled via `caBundle` or `caProvider`. However, a direct equivalent to `insecureSkipVerify: true` appears to be missing or moved in the `v1` schema for the Vault provider.

## Resolution
**FIXED (2026-02-27)** — Vault is deployed with HTTP internally (`http://vault.vault.svc:8200` per `scripts/etc/vault/vars.sh`). The test was incorrectly using `https://` with `insecureSkipVerify: true`. Fixed by switching server URL to `http://` and removing the `tls` block entirely — no TLS negotiation, no schema issue.

## Evidence
`kubectl explain clustersecretstore.spec.provider.vault.tls` output shows no `insecureSkipVerify` field.
