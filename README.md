# k3d-manager

Modular Bash utility for creating and managing local Kubernetes development clusters. Supports a **two-cluster architecture** — an infra cluster (Vault, ESO, Istio, Jenkins, ArgoCD, OpenLDAP, Keycloak) and an app cluster (Ubuntu k3s) managed via ArgoCD GitOps.

The entry point is `./scripts/k3d-manager`, which dispatches to core libraries and lazily loads plugins on demand. On macOS with OrbStack running, the `orbstack` provider is auto-selected; otherwise `k3d` is the default. Linux hosts use `CLUSTER_PROVIDER=k3s`.

The project includes an **Agent Rigor Protocol** (`_agent_checkpoint`, `_agent_lint`, `_agent_audit`) that enforces spec-first development, architectural linting, and security checks on every commit via a pre-commit hook.

![Three AI agents — Codex, Gemini, and Claude — working simultaneously on k3d-manager](docs/assets/multi-agents.png)

---

## Quick Start: Two-Cluster Journey

### 1. Bootstrap the infra cluster (local — OrbStack or k3d)

```bash
./scripts/k3d-manager deploy_cluster --confirm          # create cluster + install Istio
./scripts/k3d-manager deploy_vault --confirm            # Vault HA + PKI
./scripts/k3d-manager deploy_eso --confirm              # External Secrets Operator
./scripts/k3d-manager deploy_ldap --confirm             # OpenLDAP directory
./scripts/k3d-manager deploy_argocd --confirm           # ArgoCD GitOps engine
ENABLE_JENKINS=1 ./scripts/k3d-manager deploy_jenkins --enable-vault            # Jenkins + Vault auth
./scripts/k3d-manager deploy_keycloak --confirm         # Keycloak identity provider
ACME_EMAIL=you@example.com \
  ./scripts/k3d-manager deploy_cert_manager --confirm   # cert-manager + ACME ClusterIssuer
```

### 2. Provision the ACG sandbox (app cluster on AWS EC2)

```bash
# Extract AWS credentials from the Pluralsight sandbox (run before acg_provision)
./scripts/k3d-manager acg_get_credentials              # Playwright auto-extract via Chrome CDP
pbpaste | ./scripts/k3d-manager acg_import_credentials # fallback: paste from clipboard

acg_provision --confirm           # VPC + SG + key pair + t3.medium EC2; updates ~/.ssh/config
acg_status                        # verify instance state + k3s health
acg_extend                        # open browser to extend sandbox TTL (+4h)
acg_teardown --confirm            # terminate instance; remove ubuntu-k3s kubeconfig context
```

> Set `ACG_ALLOWED_CIDR=<your-ip>/32` to restrict SSH/6443 ingress (default: `0.0.0.0/0`).
>
> **First run:** `acg_extend_playwright` will open Google Chrome and prompt for Pluralsight login as needed. Log in manually — the session cookie persists across runs until it expires. Set `K3DM_ACG_SKIP_SESSION_CHECK=1` to bypass the browser session check.

### 3. Add the Ubuntu k3s app cluster

```bash
UBUNTU_K3S_SSH_HOST=ubuntu \
  ./scripts/k3d-manager add_ubuntu_k3s_cluster    # export kubeconfig + register in ArgoCD
./scripts/k3d-manager configure_vault_app_auth    # cross-cluster Vault auth
./scripts/k3d-manager register_shopping_cart_apps # deploy shopping cart via ArgoCD
```

### 4. Verify

```bash
./scripts/k3d-manager test all    # run all BATS suites
```

---

## Usage

```bash
./scripts/k3d-manager                     # short summary: categories + function counts
./scripts/k3d-manager --help              # full function list grouped by category
./scripts/k3d-manager <function> [args]   # invoke a core or plugin function
```

Running without arguments prints a concise overview:

```
Usage: ./k3d-manager <function> [args]

Categories:
  Cluster lifecycle      (9 functions)
  Infrastructure         (5 functions)
  Secrets                (7 functions)
  Directory service      (9 functions)
  Networking             (4 functions)
  Shopping cart          (2 functions)
  Testing                (9 functions)

Run ./scripts/k3d-manager --help for full function list.
```

`--help` expands each category with the full function list, cluster provider info, and environment variables.

```bash
./scripts/k3d-manager create_cluster mycluster          # default 8000/8443
./scripts/k3d-manager create_cluster second 9090 9443   # custom ports
CLUSTER_PROVIDER=k3s ./scripts/k3d-manager deploy_cluster -f   # k3s, non-interactive
```

### Safety Gates, Dry-Run, and Plans

- Running any `deploy_*` function with no arguments now shows the help text instead of executing. Pass explicit options or `--confirm` to apply the defaults, e.g. `./scripts/k3d-manager deploy_vault --confirm --namespace secrets`.
- Add `--dry-run` (or `-n`) to print every command that would run without executing, useful for reviewing changes or validating permissions. Sets `K3DM_DEPLOY_DRY_RUN=1`—set it in the environment to dry-run full sessions.
- `deploy_vault --plan` inspects the current cluster state (namespace, Helm release, Vault status, PKI/policy setup) and prints a Terraform-style plan before you run the real deployment.

---

## Provider Selection

| Provider | When | How |
|---|---|---|
| `orbstack` | macOS + OrbStack running | Auto-detected (or `CLUSTER_PROVIDER=orbstack`) |
| `k3d` | macOS, no OrbStack | Default fallback |
| `k3s` | Linux bare-metal | `CLUSTER_PROVIDER=k3s` |
| `k3s-aws` | AWS EC2 via ACG sandbox | `CLUSTER_PROVIDER=k3s-aws` |
| `k3s-gcp` | GCP compute instance via ACG sandbox | `CLUSTER_PROVIDER=k3s-gcp` |

See **[docs/providers/](docs/providers/)** for per-provider guides:
- [OrbStack](docs/providers/orbstack.md)
- [k3s (bare-metal)](docs/providers/k3s.md)
- [k3s-aws / k3s-gcp (ACG sandbox)](docs/howto/acg.md)

---

## Architecture

![k3d-manager Framework](docs/architecture/k3d-framework.png)

```mermaid
graph TD
  U[User CLI] --> KM[./scripts/k3d-manager]
  KM --> LIB["lib/ — system · core · providers"]
  KM --|lazy-load|--> PLUG["plugins/ — acg · aws · gemini · tunnel · ..."]

  subgraph Infra ["Infra Cluster — OrbStack / k3d / k3s (local)"]
    VAULT["Vault (PKI + Auth)"]
    ESO[ESO]
    ARGOCD[ArgoCD]
    JENKINS[Jenkins]
    ISTIO[Istio]
    LDAP[LDAP / AD]
    ESO -->|sync| VAULT
  end

  subgraph AppCluster ["App Cluster — k3s-aws (EC2)"]
    K3S[k3s node]
    APPS[Shopping Cart pods]
    K3S --> APPS
  end

  ANTG["Chrome (Playwright CDP :9222)"]
  AWSC["aws.sh — credential import"]

  PLUG -->|deploy stack| Infra
  PLUG -->|acg_provision — EC2 + k3sup| AppCluster
  PLUG -->|browser automation| ANTG
  PLUG -->|credential import| AWSC
  ANTG -->|extract from Pluralsight| AWSC
  AWSC -->|auth| AppCluster
  PLUG -.->|tunnel.sh — autossh :6443| K3S
  ARGOCD -->|GitOps deploy| APPS
  VAULT -.->|cross-cluster auth| K3S
  ESO -.->|sync| AKV[Azure Key Vault]
```

---

## Directory Layout

```
scripts/
  k3d-manager        # dispatcher
  lib/               # core functionality (system.sh, core.sh, cluster_provider.sh)
  plugins/           # optional features loaded on demand
  etc/               # templates and configs (*.yaml.tmpl, vars.sh)
  tests/             # BATS suites (pure logic — no cluster mocks)
bin/                 # one-off convenience scripts (also exposed as Claude skills)
  acg-up             # full provision: creds → cluster → tunnel → watcher → ghcr-pull-secret
  acg-down           # teardown: tunnel stop → CloudFormation delete
  acg-refresh        # refresh AWS credentials + restart tunnel (daily driver)
  acg-status         # read-only snapshot: tunnel, nodes, pods, ArgoCD, AWS creds
  rotate-ghcr-pat    # update PACKAGES_TOKEN in all shopping-cart repos via stdin
docs/
  architecture/      # design documents
  api/               # function reference and Vault PKI config
  guides/            # jenkins auth, plugin development
  providers/         # orbstack, k3s provider guides
  plans/             # feature planning and specifications
  howto/             # user guides
  issues/            # tracked bugs and debt
```

---

## Documentation

### API Reference
- **[Public Functions](docs/api/functions.md)** — All callable functions with source locations
- **[Vault PKI Configuration](docs/api/vault-pki.md)** — PKI variables, example workflow, air-gapped setup

### Plugins

| Plugin | Key Functions | Description |
|---|---|---|
| **ACG** | `acg_get_credentials`, `acg_import_credentials`, `acg_provision`, `acg_status`, `acg_extend`, `acg_extend_playwright`, `acg_watch`, `acg_teardown` | AWS/GCP ACG sandbox lifecycle — automated credential extraction via Playwright CDP, stdin fallback, cloud VM provisioning, background TTL watcher; [spec](docs/plans/archive/v0.9.6-acg-plugin.md) |
| **AWS** | `aws_import_credentials` | Generic AWS credential import — supports CSV (IAM Download), quoted/unquoted export, labeled (Pluralsight), credentials file formats; writes `~/.aws/credentials` |
| **Gemini** | `gemini_install`, `gemini_trigger_copilot_review`, `gemini_poll_task` | Browser automation via gemini CLI + Playwright over CDP (port 9222) — Copilot coding agent trigger |
| **ArgoCD** | `deploy_argocd`, `deploy_argocd_bootstrap`, `register_app_cluster`, `configure_vault_argocd_repos` | GitOps engine deployment + app cluster registration + Vault repo auth |
| **Vault** | `deploy_vault`, `configure_vault_app_auth` | HashiCorp Vault HA + PKI + cross-cluster auth |
| **ESO** | `deploy_eso` | External Secrets Operator — syncs Vault/AKV secrets into Kubernetes |
| **Jenkins** | `deploy_jenkins` | Jenkins StatefulSet + Vault sidecar + ESO cert rotation CronJob |
| **LDAP** | `deploy_ldap`, `deploy_ad`, `ldap_get_user_password` | OpenLDAP or Active Directory directory service |
| **Keycloak** | `deploy_keycloak`, `test_keycloak` | Keycloak identity provider + smoke test |
| **cert-manager** | `deploy_cert_manager` | cert-manager + ACME ClusterIssuer (Let's Encrypt) |
| **vCluster** | `vcluster_create`, `vcluster_destroy`, `vcluster_use`, `vcluster_list` | Virtual cluster lifecycle on top of the infra cluster |
| **Tunnel** | `tunnel_start`, `tunnel_stop`, `tunnel_status` | autossh persistent tunnel with launchd boot persistence |
| **Azure** | `create_az_sp`, `deploy_azure_eso`, `eso_akv` | Azure Service Principal + ESO with Azure Key Vault backend |
| **SMB CSI** | `deploy_smb_csi` | SMB CSI driver for Windows-compatible persistent volumes |
| **Shopping Cart** | `register_shopping_cart_apps`, `deploy_app_cluster` | Demo app cluster bootstrap — k3sup EC2 install + ArgoCD app registration |
| **SSM** | `ssm_wait`, `ssm_exec`, `ssm_tunnel` | AWS Systems Manager helpers — wait for SSM registration, run commands on EC2, open SSM port-forward tunnel; opt-in via `K3S_AWS_SSM_ENABLED=true` |
| **Hello** | `hello` | Minimal example plugin — Hello World; reference for new plugin authors |

### Guides
- **[Jenkins Authentication](docs/guides/jenkins-authentication.md)** — Auth modes (built-in / LDAP / AD), Vault sidecar, password rotation
- **[Plugin Development](docs/guides/plugin-development.md)** — Writing plugins, `_run_command` helper, testing
- **[Jenkins Job DSL Setup](docs/jenkins-job-dsl-setup.md)** — Seed job + GitHub repo wiring
- **[Copilot Review Process](docs/guides/copilot-review-process.md)** — When to request, severity levels, handling findings, pre-merge checklist
- **[Copilot Review Template](docs/guides/copilot-review-template.md)** — Fill-in template for per-PR review records

### Providers
- **[OrbStack](docs/providers/orbstack.md)** — macOS auto-detection and manual override
- **[k3s (bare-metal)](docs/providers/k3s.md)** — Auto-install, existing cluster, k3d vs k3s differences

### Architecture
- **[Configuration-Driven Design](docs/architecture/configuration-driven-design.md)** — Core design principle
- **[Strategic Roadmap v1.0](docs/plans/archive/roadmap-v1.md)** — v0.8.0 → v1.0.0 roadmap
- **[Two-Cluster Architecture](docs/plans/two-cluster-infra.md)** — Infra + app cluster design

### How-To

**Secrets & Identity**
- **[Vault](docs/howto/vault.md)** — Deploy, init, PKI cert issuance, cross-cluster auth
- **[ESO](docs/howto/eso.md)** — Deploy, connect a secret store, troubleshoot sync failures
- **[Keycloak](docs/howto/keycloak.md)** — Deploy, smoke test, LDAP federation

**GitOps & CI/CD**
- **[ArgoCD](docs/howto/argocd.md)** — Deploy, register app cluster, configure deploy keys
- **[cert-manager](docs/howto/cert-manager.md)** — Deploy, Vault + ACME issuers, certificate lifecycle

**Cloud Sandbox**
- **[ACG Sandbox](docs/howto/acg.md)** — Full lifecycle: provision → k3s install → extend TTL → teardown
- **[Gemini Browser Automation](docs/howto/gemini.md)** — First-run setup, ACG extend, Copilot agent trigger
- **[ACG Credentials Flow](docs/howto/acg-credentials-flow.md)** — Decision-by-decision flow reference for debugging `acg_get_credentials`

**Convenience Scripts** (`bin/` — also available as Claude `/skills`)

- **[Makefile Reference](docs/howto/makefile.md)** — All `make` targets with usage, env vars, and when to use each

| Script | Claude Skill | When to use |
|---|---|---|
| `bin/acg-up [--login-prompt]` | `/acg-up` | Start from scratch — full provision + ghcr-pull-secret |
| `bin/acg-down --confirm` | `/acg-down` | Tear down cluster and tunnel |
| `bin/acg-refresh [--login-prompt]` | `/acg-refresh` | Creds expired or tunnel dropped — daily driver |
| `bin/acg-status` | `/acg-status` | Read-only health check — nodes, pods, ArgoCD, AWS |
| `bin/rotate-ghcr-pat` | — | Rotate `PACKAGES_TOKEN` in all shopping-cart repos |

> `GHCR_PAT` env var must be set before `acg-up` (used to create `ghcr-pull-secret`).
> Pass tokens via `pbpaste | bin/rotate-ghcr-pat` — never paste into chat.

**Virtual Clusters**
- **[vCluster](docs/howto/vcluster.md)** — Create, use, list, and destroy virtual Kubernetes clusters inside the infra cluster

**Networking**
- **[SSH Tunnel](docs/howto/tunnel.md)** — autossh setup, launchd boot persistence, app cluster access

**Jenkins**
- **[Configuring SSL Trust for jenkins-cli](docs/howto/jenkins-cli-ssl-trust.md)** — Trust Vault-issued certs for `jenkins-cli.jar`
- **[Jenkins K8s Agents Testing](docs/howto/jenkins-k8s-agents-testing.md)** — Verify dynamic pod agents in the infra cluster

**LDAP / Directory**
- **[LDAP Bulk User Import](docs/howto/ldap-bulk-user-import.md)** — Import users from a CSV into OpenLDAP
- **[LDAP Password Rotation](docs/howto/ldap-password-rotation.md)** — Rotate user passwords via the rotator CronJob

---

## Issue Logs

All tracked bugs, investigations, and debt are filed in **[docs/issues/](docs/issues/)** — one Markdown file per incident.

Recent entries:

| Date | Issue | Component |
|---|---|---|
| 2026-04-30 | [GHCR secret rotation fallback fails open](docs/issues/2026-04-30-ghcr-secret-rotation-fallback-fails-open.md) | acg-up, rotate-ghcr-pat — `gh auth token` OAuth fallback recreates invalid pull secret; fix: fail closed, Vault-first |
| 2026-04-29 | [ACG Watcher extend button not found](docs/issues/2026-04-29-acg-watcher-extend-button-not-found.md) | lib-acg watcher — button not located during 1h TTL window; manual sequence documented |
| 2026-04-29 | [gh auth token insufficient scope for GHCR](docs/issues/2026-04-29-gh-auth-token-insufficient-scope-for-ghcr.md) | acg-up — OAuth token lacks `read:packages`; resolved via Vault-first PAT strategy |
| 2026-04-28 | [ClusterSecretStore vault-bridge pod-origin empty reply](docs/issues/2026-04-28-clustersecretstore-vault-bridge-pod-traffic-empty-reply.md) | vault-bridge — pod-origin traffic returns empty reply; `ClusterSecretStore/vault-backend` stays `Ready=False` |
| 2026-04-28 | [Vault sealed health misclassified as unreachable](docs/issues/2026-04-28-acg-up-vault-sealed-health-misclassified.md) | acg-up — sealed Vault returns non-2xx; `curl -f` discarded JSON; auto-recover via `--re-unseal` |

[All issues →](docs/issues/)

---

## Releases

| Version | Date | Highlights |
|---|---|---|
| [v1.2.0](https://github.com/wilddog64/k3d-manager/releases/tag/v1.2.0) | 2026-04-30 | lib-acg extraction + shopping-cart bootstrap + GHCR hardening — ACG/GCP automation extracted to `scripts/lib/acg/` subtree; `deploy_shopping_cart_data()` in `acg-up`; Vault-first GHCR fail-closed; ArgoCD launchd port-forward; ApplicationSet branch var; Vault sealed-state recovery |
| [v1.1.0](https://github.com/wilddog64/k3d-manager/releases/tag/v1.1.0) | 2026-04-24 | Unified ACG automation AWS + GCP — GCP provider (`k3s-gcp`), OAuth automation, CDP headless Linux, `bin/acg-sync-apps` port-forward hardening, Hub auto-create + bootstrap, provider-aware teardown |
| [v1.0.6](https://github.com/wilddog64/k3d-manager/releases/tag/v1.0.6) | 2026-04-11 | AWS SSM support — `ssm_wait`/`ssm_exec`/`ssm_tunnel` helpers; `K3S_AWS_SSM_ENABLED` opt-in; IAM role + instance profile in CloudFormation; `--capabilities CAPABILITY_NAMED_IAM` fix; `make ssm`/`provision` targets |

<details>
<summary>Older releases</summary>

| Version | Date | Highlights |
|---|---|---|
| [v1.0.4](https://github.com/wilddog64/k3d-manager/releases/tag/v1.0.4) | 2026-04-10 | ACG extend hardening — button-first search; midnight date-wrap fix; random passwords in `bin/acg-up`; sandbox-expired guidance in `_acg_check_credentials`; Pluralsight URL standardization |
| [v1.0.3](https://github.com/wilddog64/k3d-manager/releases/tag/v1.0.3) | 2026-04-05 | ACG full stack fixes — ESO 1.0.0; ClusterSecretStore `v1`; ArgoCD context + server URL fix; `GHCR_PAT` masking; Chrome CDP launchd agent; `make sync-apps` + `make argocd-registration` |
| [v1.0.2](https://github.com/wilddog64/k3d-manager/releases/tag/v1.0.2) | 2026-04-03 | full stack automation — `make up` 12-step provision; Vault port-forward; vault-bridge Service; argocd-manager bootstrap; helm + ESO install; `bin/` SCRIPT_DIR fix |
| [v1.0.1](https://github.com/wilddog64/k3d-manager/releases/tag/v1.0.1) | 2026-03-31 | multi-node k3s-aws + CloudFormation + Playwright hardening — 3-node CF stack; auto sign-in; remove Antigravity pre-calls from `acg_get_credentials`; `AGENT_IP_ALLOWLIST` in pre-commit hook |
| [v1.0.0](https://github.com/wilddog64/k3d-manager/releases/tag/v1.0.0) | 2026-03-29 | k3s-aws provider foundation — `CLUSTER_PROVIDER=k3s-aws` end-to-end deploy; `aws_import_credentials`; `acg_provision --recreate`; `acg_watch` background TTL watcher; keypair idempotency + `page.goto()` fix |
| [v0.9.21](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.21) | 2026-03-29 | `_ensure_k3sup` auto-install helper — `deploy_app_cluster` now auto-installs k3sup via brew or curl; consistent with `_ensure_node`/`_ensure_copilot_cli` pattern |
| [v0.9.20](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.20) | 2026-03-29 | ACG Chrome launch fix — `_antigravity_launch` now opens Chrome (not browser IDE) with `--password-store=basic`; `acg_credentials.js` SPA nav guard avoids hard reload |
| [v0.9.19](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.19) | 2026-03-28 | ACG automated credential extraction — `acg_get_credentials` (Playwright CDP), `acg_import_credentials` (stdin), static `acg_credentials.js`; live-verified against Pluralsight sandbox |
| [v0.9.18](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.18) | 2026-03-28 | Pluralsight URL migration — `_ACG_SANDBOX_URL` + `_antigravity_ensure_acg_session` updated to `app.pluralsight.com` |
| [v0.9.17](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.17) | 2026-03-27 | Antigravity model fallback (`gemini-2.5-flash` first), ACG session check, nested agent fix (`--approval-mode yolo` + workspace temp path) |
| [v0.9.16](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.16) | 2026-03-26 | Gemini browser automation + CDP browser automation — gemini CLI + Playwright engine; `gemini_install`, `gemini_trigger_copilot_review`, `gemini_acg_extend`; ldap stdin hardening |
| [v0.9.11](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.11) | 2026-03-22 | dynamic plugin CI — `detect` job skips cluster tests for docs-only PRs; maps plugin changes to targeted smoke tests |
| [v0.9.10](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.10) | 2026-03-22 | if-count allowlist elimination (jenkins) — 8 helpers extracted; allowlist now `system.sh` only |
| [v0.9.9](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.9) | 2026-03-22 | if-count allowlist elimination — 11 ldap helpers + 6 vault helpers extracted; allowlist down to `system.sh` only |
| [v0.9.7](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.7) | 2026-03-22 | lib-foundation sync (`--interactive-sudo`, `_run_command_resolve_sudo`), `deploy_cluster` no-args guard, `bin/` `_kubectl` wrapper, BATS stub fixes, Copilot PR #41 findings |
| [v0.9.6](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.6) | 2026-03-22 | ACG sandbox plugin (`acg_provision/status/extend/teardown`), VPC/SG idempotency, `ACG_ALLOWED_CIDR` security, kops-for-k3s reframe |
| [v0.9.5](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.5) | 2026-03-21 | `deploy_app_cluster` — EC2 k3sup install + kubeconfig merge + ArgoCD registration; replaces manual rebuild |
| [v0.9.4](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.4) | 2026-03-21 | autossh tunnel plugin, ArgoCD cluster registration, smoke-test gate, `_run_command` TTY fallback, lib-foundation v0.3.3 |
| [v0.9.3](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.3) | 2026-03-16 | TTY fix (`_DCRS_PROVIDER` global), lib-foundation v0.3.2 subtree, cluster rebuild smoke test |
| [v0.9.2](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.2) | 2026-03-15 | vCluster E2E composite actions, 11-finding Copilot hardening (curl safety, mktemp, sudo -n, input validation) |
| [v0.9.1](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.1) | 2026-03-15 | vCluster plugin (`create/destroy/use/list`), two-tier `--help`, `function test()` refactor, 11 Copilot findings fixed |
| [v0.9.0](https://github.com/wilddog64/k3d-manager/releases/tag/v0.9.0) | 2026-03-15 | k3dm-mcp planning, agent workflow lessons, roadmap restructure |
| [v0.8.0](https://github.com/wilddog64/k3d-manager/releases/tag/v0.8.0) | 2026-03-13 | Vault-managed ArgoCD deploy keys, `deploy_cert_manager` (ACME/Let's Encrypt), Istio IngressClass |

[Full release history →](docs/releases.md)

</details>
