# Makefile Reference — k3d-manager

All targets operate on the **current `CLUSTER_PROVIDER`** set in your environment
(default: `k3s-aws`). Override the sandbox URL with `URL=https://...`.

```bash
make up                      # provision full stack (default URL)
make up URL=https://...      # provision with explicit sandbox URL
```

---

## Core Lifecycle

| Target | Command | When to use |
|---|---|---|
| `make up` | `bin/acg-up` | Start from scratch — credentials → Hub cluster → ESO → ArgoCD → app cluster |
| `make down` | `bin/acg-down --confirm` | Tear down app cluster, Hub cluster, and Vault port-forward |
| `make refresh` | `bin/acg-refresh` | Creds expired or tunnel dropped — re-extracts credentials and restarts tunnel |
| `make status` | `bin/acg-status` | Read-only health check — Hub nodes, pods, tunnel, ArgoCD |

---

## ArgoCD

| Target | When to use |
|---|---|
| `make sync-apps` | Sync `rollout-demo-default` in ArgoCD and show remote pod status |
| `make argocd-registration` | Re-register the app cluster with ArgoCD after sandbox recreation or IP change |

`sync-apps` delegates to `bin/acg-sync-apps` which manages the argocd-server port-forward
automatically (reuses an existing one, starts a new one if needed).

`argocd-registration` reads the `ubuntu-k3s` kubeconfig, switches to `k3d-k3d-cluster`
context, calls `register_app_cluster`, and restarts the ArgoCD application controller.

---

## Credential Extraction

| Target | When to use |
|---|---|
| `make creds` | Extract AWS/GCP credentials only — no cluster changes |
| `make chrome-cdp` | Install macOS Chrome CDP launchd agent (persistent CDP session on boot) |
| `make chrome-cdp-stop` | Uninstall the launchd agent |

`make creds` calls `acg_get_credentials` directly — useful for refreshing short-lived
credentials without touching the cluster.

`make chrome-cdp` installs a `launchd` plist so Chrome starts with CDP flags on login,
enabling headless credential automation without a manual browser launch.

---

## AWS SSM

| Target | When to use |
|---|---|
| `make ssm` | Ensure `session-manager-plugin` is installed (required for SSM-based workflows) |
| `make provision` | Provision the ACG CloudFormation stack with SSM support (depends on `ssm`) |

`make provision` is equivalent to `K3S_AWS_SSM_ENABLED=true scripts/k3d-manager acg_provision --confirm`.
It installs the SSM plugin first via `make ssm` then provisions the full CloudFormation stack.

---

## Help

```bash
make help    # print all targets with one-line descriptions
make         # same as make help (DEFAULT_GOAL)
```

---

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `URL` | `https://app.pluralsight.com/cloud-playground/cloud-sandboxes` | Sandbox URL passed to `bin/acg-up` and `bin/acg-refresh` |
| `GHCR_PAT` | `$(gh auth token)` | GitHub Container Registry token — used by `acg-up` to create the `ghcr-pull-secret` |

Set `GHCR_PAT` before running `make up`:

```bash
export GHCR_PAT=$(gh auth token)
make up
```
