# Status login checks used stale credentials

## What was tested

`make status` reported HTTP 200 for the public endpoints but failed Keycloak,
ArgoCD, and Grafana login checks. The webhook process also lost its local
Keychain token during restart.

## Root cause

The webhook login smoke checks did not read the current Vault-managed ArgoCD
and Grafana credentials, and looked for the Keycloak smoke secret without the
hub context. In addition, the webhook LaunchAgent template left `{{HOME}}`
literal in `KUBECONFIG`, so Kubernetes secret lookups from launchd failed.

## Fix

- Read the Keycloak smoke secret from the hub `k3d-k3d-cluster` context.
- Read current ArgoCD and Grafana credentials from the local Vault KV API,
  with hub-secret fallback.
- Substitute `${HOME}` when rendering the webhook LaunchAgent plist.

## Verification

After reinstalling/restarting the webhook LaunchAgent:

```text
✓ Keycloak login: token minted (realm=shopping-cart)
✓ Frontend login: HTTP 200 on /api/cart
✓ ArgoCD login: HTTP 200
✓ Grafana login: HTTP 200
Overall: HEALTHY
```

The remaining optional-service checks also passed in the live verification.
