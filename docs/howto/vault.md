# How-To: HashiCorp Vault

Vault provides secrets management and PKI for the infra cluster. k3d-manager deploys Vault in HA mode with a Raft storage backend and configures a PKI engine for TLS certificate issuance.

## Prerequisites

- Infra cluster running (`deploy_cluster`)
- `helm` and `kubectl` in PATH

## Deploy Vault

```bash
./scripts/k3d-manager deploy_vault --confirm
```

This installs Vault via Helm, initializes the Raft cluster, unseals automatically, and configures:
- KV v2 secret store at `secret/`
- PKI engine with a root CA and an intermediate issuer
- Kubernetes auth mount for the infra cluster

To review what will be applied without executing:
```bash
./scripts/k3d-manager deploy_vault --plan
```

## Cross-Cluster Auth (app cluster)

After the app cluster (Ubuntu k3s) is registered:

```bash
./scripts/k3d-manager configure_vault_app_auth
```

This registers a second Kubernetes auth mount for the app cluster, allowing pods on Ubuntu k3s to authenticate to Vault using their ServiceAccount tokens.

## PKI — Issue a Certificate

```bash
vault write pki_int/issue/k3d-manager \
  common_name="myservice.svc.cluster.local" \
  ttl="720h"
```

See **[Vault PKI Configuration](../api/vault-pki.md)** for full PKI variable reference, air-gapped setup, and example workflows.

## Common Operations

```bash
# Check Vault status
kubectl exec -n secrets vault-0 -- vault status

# Re-unseal after restart
./scripts/k3d-manager deploy_vault --confirm   # idempotent — safe to re-run

# Rotate root token (manual — store securely)
vault token create -policy=root -period=0
```

## Notes

- Vault tokens must never appear in script arguments or CI logs — use env vars or stdin
- Leaf cert TTL is capped at 720h by default (`VAULT_PKI_ROLE_TTL`) — do not increase without justification
