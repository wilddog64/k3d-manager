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
# then use it for terminal smoke tests or CLI login only

# Browser entrypoint (canonical host)
# open https://argocd.shopping-cart.local
```

The localhost port-forward remains useful for terminal smoke tests and CLI login.
Do not use it as the browser SSO entrypoint.

The canonical browser entrypoint is `https://argocd.shopping-cart.local`, which
is backed by a local TLS listener on port 443. The listener uses a Vault PKI
certificate for `argocd.shopping-cart.local`; if Safari does not yet trust the
Vault CA, run `bin/setup-vault-ca -m` to install it into the macOS keychain.

### Trust the Hub Vault CA (`make trust-vault-ca`)

`make trust-vault-ca` (`bin/cluster-up --trust-vault-ca`) trusts the Hub Vault PKI root CA in the macOS
System Keychain:

- It uses `~/.local/share/k3d-manager/acg/argocd-browser-https-tls/ca.crt`, or reads `pki/cert/ca` from the hub's
  Vault when that file is missing.
- It does nothing when the CA is already trusted (`security verify-cert`), or on a host that is not macOS.
- Otherwise it runs `security add-trusted-cert -d -r trustRoot` through `_run_command --interactive-sudo`.

macOS asks for approval through SecurityAgent, so run it from a local terminal on the Mac. Over SSH, or with no TTY,
it stops with an error that says so. `acg-up` skips this step in those sessions and warns you to run
`make trust-vault-ca` yourself. The webhook exposes the target to the `admin` role only.

## Notes

- ArgoCD runs on the **infra cluster** (`k3d-k3d-cluster` context) and deploys to the **app cluster** (`ubuntu-k3s` context)
- All Application CRs live in the `cicd` namespace on the infra cluster
- Deploy keys are rotated via `configure_vault_argocd_repos` — never commit SSH keys to git
