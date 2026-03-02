# Active Context – k3d-manager

## Current Branch: `feature/app-cluster-deploy` (as of 2026-03-01)

**v0.5.0 merged** — Keycloak plugin complete + ARM64 image fix. Infra cluster fully deployed.
**v0.6.0 in progress** — `configure_vault_app_auth` implemented. PR #16 open; CI green, Copilot review resolved (4 findings fixed — commit `b9bda33`), awaiting owner merge.

---

## Current Focus

**v0.6.0: App Cluster Deployment**

Steps:
1. `configure_vault_app_auth` — **DONE** (PR open, awaiting merge)
2. ESO deploy on Ubuntu app cluster — Gemini SSH (after PR merges)
3. shopping-cart-data (PostgreSQL, Redis, RabbitMQ) — Gemini SSH
4. shopping-cart-apps (basket, order, payment, catalog, frontend) — Gemini SSH

---

## Cluster State (as of 2026-03-01)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)

| Component | Status | Notes |
|---|---|---|
| Vault | Running | `secrets` ns, initialized + unsealed |
| ESO | Running | `secrets` ns |
| OpenLDAP | Running | `identity` ns |
| Istio | Running | `istio-system` |
| Jenkins | Running | `cicd` ns |
| ArgoCD | Running | `cicd` ns (v0.4.0) |
| Keycloak | Running | `identity` ns (v0.5.0) |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`)

| Component | Status | Notes |
|---|---|---|
| k3s node | Ready | v1.34.4+k3s1 |
| Istio | Running | IngressGateway + istiod |
| ESO | Pending | Deploy after PR merges |
| shopping-cart-data | Pending | PostgreSQL, Redis, RabbitMQ |
| shopping-cart-apps | Pending | basket, order, payment, catalog, frontend |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Release Strategy

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.5.0 | released | See CHANGE.md |
| v0.6.0 | PR open | configure_vault_app_auth + vault_app_auth.bats |
| v0.7.0 | future | Keycloak provider interface; cluster rename to `infra` |

---

## Open Items

- [x] `configure_vault_app_auth` — implemented + Copilot review resolved (PR #16, CI green, awaiting merge)
- [ ] ESO deploy on Ubuntu app cluster (Gemini — SSH, after PR merges)
- [ ] shopping-cart-data / apps deployment on Ubuntu (Gemini — SSH)
- [ ] GitGuardian: mark 2026-02-28 incident as false positive (owner action)
- [ ] `scripts/tests/plugins/jenkins.bats` — backlog
- [ ] v0.7.0: rename cluster to `infra` + fix `CLUSTER_NAME` env var

---

## Operational Notes

- **Pipe all command output to `scratch/logs/<cmd>-<timestamp>.log`** — always print log path before starting
- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **Vault reboot unseal**: dual-path — macOS Keychain + Linux libsecret; k8s `vault-unseal` secret is fallback
- **New namespace defaults**: `secrets`, `identity`, `cicd` — old names still work via env var override
- **Branch protection**: `enforce_admins` permanently disabled — owner can self-merge
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64 — `docker.io/bitnami/*` and `public.ecr.aws/bitnami/*` are broken/amd64-only

---

## Agent Workflow (canonical)

```
Claude
  -- monitors CI / reviews agent reports for accuracy
  -- opens PR on owner go-ahead
  -- when CI fails: identifies root cause → writes bug report → hands to Gemini

Gemini
  -- investigates, fixes code, verifies live (shellcheck + bats + cluster)
  -- handles Ubuntu SSH deployment (interactive)
  -- may write back stale memory bank — always verify after

Codex
  -- pure logic fixes with no cluster dependency
  -- STOP at each verification gate; do not rationalize partial fixes

Owner
  -- approves and merges PRs
```

**Lessons learned:**
- Gemini ignores hold instructions — accept it, use review as the gate
- Gemini may write back stale memory bank content — verify file state after every update
- Codex commit-on-failure is a known failure mode — write explicit STOP guardrails
