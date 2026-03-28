# How-To: External Secrets Operator

ESO syncs secrets from Vault (or Azure Key Vault) into Kubernetes `Secret` objects. k3d-manager deploys ESO and configures it to pull from the infra cluster's Vault instance.

## Prerequisites

- Vault deployed and healthy (`deploy_vault`)
- Infra cluster running

## Deploy ESO

```bash
./scripts/k3d-manager deploy_eso
```

This installs ESO via Helm and creates a `ClusterSecretStore` backed by the Vault KV engine.

## How It Works

```
Vault KV (secret/k3d-manager/...)
        ↓  ESO ClusterSecretStore
Kubernetes Secret (in target namespace)
```

ESO polls Vault on a configurable interval. When a Vault secret changes, ESO updates the Kubernetes `Secret` automatically — no manual `kubectl create secret` needed.

## Add a New Secret

1. Write the secret to Vault:
   ```bash
   vault kv put secret/k3d-manager/myapp password=<your-password>
   ```

2. Create an `ExternalSecret` CR in your namespace:
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: myapp-secret
     namespace: myapp
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: vault-backend
       kind: ClusterSecretStore
     target:
       name: myapp-secret
     data:
       - secretKey: password
         remoteRef:
           key: secret/data/k3d-manager/myapp
           property: password
   ```

## Troubleshoot Sync Failures

```bash
# Check ESO controller logs
kubectl logs -n external-secrets deploy/external-secrets -f

# Check ExternalSecret status
kubectl describe externalsecret myapp-secret -n myapp

# Force a resync
kubectl annotate externalsecret myapp-secret -n myapp \
  force-sync=$(date +%s) --overwrite
```

## Notes

- Secrets are never stored in git — ESO pulls from Vault at runtime
- Use `ClusterSecretStore` for cross-namespace access; `SecretStore` for namespace-scoped stores
