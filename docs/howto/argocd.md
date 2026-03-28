# How-To: ArgoCD

ArgoCD is the GitOps engine. It runs on the infra cluster and manages application deployments on the app cluster (Ubuntu k3s) via hub-and-spoke.

## Prerequisites

- Infra cluster running (`deploy_cluster`)
- Vault and ESO deployed (for Vault-managed deploy keys)

## Deploy ArgoCD

```bash
./scripts/k3d-manager deploy_argocd --confirm
```

Installs ArgoCD via Helm into the `cicd` namespace. Vault-managed deploy keys are configured automatically so ArgoCD can pull from private GitHub repos.

## Bootstrap Initial Apps

```bash
./scripts/k3d-manager deploy_argocd_bootstrap
```

Applies the root App-of-Apps manifest — ArgoCD self-manages its own app definitions from that point forward.

## Register the App Cluster (Ubuntu k3s)

After `deploy_app_cluster` completes and the kubeconfig is merged:

```bash
./scripts/k3d-manager register_shopping_cart_apps
```

This registers the `ubuntu-k3s` context as a target cluster in ArgoCD and creates Application CRs for the shopping-cart services.

## Configure Vault Deploy Keys

```bash
./scripts/k3d-manager configure_vault_argocd_repos
```

Rotates the deploy keys stored in Vault and updates ArgoCD's repository credentials. Run this after any Vault PKI rotation.

## Common Operations

```bash
# Check all application sync status
kubectl get applications -n cicd

# Force sync a specific app
argocd app sync <app-name>

# View sync history
argocd app history <app-name>

# Access ArgoCD UI (port-forward)
kubectl port-forward svc/argocd-server -n cicd 8080:443
# then open https://localhost:8080
```

## Notes

- ArgoCD runs on the **infra cluster** (`k3d-k3d-cluster` context) and deploys to the **app cluster** (`ubuntu-k3s` context)
- All Application CRs live in the `cicd` namespace on the infra cluster
- Deploy keys are rotated via `configure_vault_argocd_repos` — never commit SSH keys to git
