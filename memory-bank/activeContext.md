# Active Context – k3d-manager

## Current Branch: `feature/argocd-phase1` (as of 2026-03-01)

**v0.3.1 merged** — Jenkins `cicd` namespace fix.

---

## Current Focus

Phase 1: Wire up ArgoCD for `cicd` namespace. Plugin + templates already exist;
Codex needs to fix stale cluster-dump manifests and add Vault secret seeding.

**Codex task spec:** `docs/plans/argocd-phase1-codex-task.md`

---

## Cluster State (as of 2026-03-01)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)
**Note:** Cluster name is `k3d-cluster` (CLUSTER_NAME=automation env var ignored — see open bug).

| Component | Status | Notes |
|---|---|---|
| Vault | ✅ Running | `secrets` ns, initialized + unsealed |
| ESO | ✅ Running | `secrets` ns |
| OpenLDAP | ✅ Running | `identity` ns |
| Istio | ✅ Running | `istio-system` |
| Jenkins | ✅ Running | `cicd` ns — smoke test passed (v0.3.1) |
| ArgoCD | ❌ Not deployed | Awaiting Phase 1 PR merge |
| Keycloak | ❌ Not deployed | no `deploy_keycloak` command yet |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`)
| Component | Status | Notes |
|---|---|---|
| k3s node | ✅ Ready | v1.34.4+k3s1 |
| Istio | ✅ Running | IngressGateway + istiod |
| ESO | ❌ Pending | Deploy after `configure_vault_app_auth` PR merges |
| shopping-cart-data | ❌ Pending | PostgreSQL, Redis, RabbitMQ |
| shopping-cart-apps | ❌ Pending | basket, order, payment, catalog, frontend |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Codex Task — ArgoCD Phase 1 (Active)

**Branch:** `feature/argocd-phase1`
**Spec:** `docs/plans/argocd-phase1-codex-task.md`
**Status:** Pending Codex implementation

### Summary of Changes Required

| File | Change |
|---|---|
| `scripts/etc/argocd/projects/platform.yaml` → `platform.yaml.tmpl` | Strip server metadata, fix namespaces (vault→secrets, jenkins→cicd, directory→identity, argocd→cicd), parameterize namespace field |
| `scripts/etc/argocd/applicationsets/platform-helm.yaml` | Strip server metadata, fix `namespace: argocd` → `cicd` |
| `scripts/etc/argocd/applicationsets/services-git.yaml` | Strip server metadata, fix `your-org` → `wilddog64`, fix `namespace: argocd` → `cicd` |
| `scripts/etc/argocd/applicationsets/demo-rollout.yaml` | Strip server metadata, fix `your-org` → `wilddog64`, fix `namespace: argocd` → `cicd` |
| `scripts/plugins/argocd.sh` — `_argocd_deploy_appproject` | Use `envsubst '$ARGOCD_NAMESPACE'` since file is now `.tmpl` |
| `scripts/plugins/argocd.sh` — add `_argocd_seed_vault_admin_secret` | Write random password to `secret/argocd/admin` in Vault if not present; call from `deploy_argocd --enable-vault` |
| `scripts/tests/plugins/argocd.bats` | New — 6 test cases (help, CLUSTER_ROLE=app skip, namespace default, missing template error) |

### What is Already Correct (do NOT change)
- `scripts/plugins/argocd.sh` — `deploy_argocd`, `deploy_argocd_bootstrap`, all other helpers
- `scripts/etc/argocd/vars.sh` — namespace is `cicd`, LDAP host is `identity` ns ✅
- `scripts/etc/argocd/values.yaml.tmpl`
- `scripts/etc/argocd/secretstore.yaml.tmpl`
- `scripts/etc/argocd/virtualservice.yaml.tmpl`
- `scripts/etc/argocd/externalsecret-admin.yaml.tmpl`
- `scripts/etc/argocd/externalsecret-ldap.yaml.tmpl`

### Verification (Codex must run)
```bash
shellcheck scripts/plugins/argocd.sh
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/argocd.bats
```

---

## Parallel Branch: `feature/app-cluster-deploy`

Codex task block in `docs/plans/app-cluster-deploy.md`.
Implements `configure_vault_app_auth` command for Ubuntu k3s ESO setup.
**Status:** Pending Codex implementation (not the current focus).

---

## Release Strategy

| Version | Status | Notes |
|---|---|---|
| v0.1.0 | ✅ released 2026-02-27 | Initial release |
| v0.2.0 | ✅ released 2026-02-27 | OrbStack, Vault reboot unseal, Jenkins k8s agents |
| v0.2.1 | ✅ released 2026-02-28 | Docs-only: CHANGE.md + README Releases table |
| v0.3.0 | ✅ merged 2026-03-01 | Two-cluster refactor, namespace renames, CLUSTER_ROLE, remote Vault ESO |
| v0.3.1 | ✅ merged 2026-03-01 | Jenkins `cicd` namespace fix — PV template + env var override |
| v0.4.0 | future | ArgoCD Phase 1 |

---

## Open Items (post v0.3.1)

- [ ] ArgoCD Phase 1 — `feature/argocd-phase1` (Codex)
- [ ] App layer deploy on Ubuntu (Gemini — SSH interactive)
- [ ] `configure_vault_app_auth` — `feature/app-cluster-deploy` (Codex)
- [ ] Keycloak deploy (no command yet)
- [ ] GitGuardian: mark 2026-02-28 incident as false positive (owner action)
- [ ] `scripts/tests/plugins/jenkins.bats` — backlog

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **LDAP bind DN**: keep `LDAP_BASE_DN` in sync with LDIF bootstrap base DN
- **Jenkins admin password**: contains special chars — always quote `-u "user:$pass"`
- **Vault reboot unseal**: dual-path — macOS Keychain + Linux libsecret; k8s `vault-unseal` secret is fallback
- **New namespace defaults**: `secrets`, `identity`, `cicd` — old names still work via env var override
- **Branch protection**: `enforce_admins` permanently disabled — owner can self-merge

---

## Agent Workflow (canonical)

```
Claude
  └── monitors CI / reviews Gemini reports for accuracy
  └── opens PR on owner go-ahead
  └── when CI fails: identifies root cause → writes bug report → hands to Gemini
  └── does NOT write fix instructions directly to Codex

Gemini
  └── receives bug report from Claude
  └── verifies root cause is correct (runs tests locally)
  └── writes Codex instructions with exact fix spec
  └── updates memory-bank with Codex task block
  └── handles Ubuntu SSH deployment (interactive)

Codex
  └── reads memory-bank Codex task block (written by Gemini or Claude for pre-verified tasks)
  └── implements fix, commits, pushes
  └── does NOT open PRs

Owner
  └── approves PR
```

**Lesson learned (2026-03-01):** Claude wrote Codex fix instructions directly,
which caused Codex to apply an over-broad fix. Bug reports should go through
Gemini for verification before Codex gets a fix spec.
**Exception:** Claude can write Codex task blocks for structural changes (manifest
cleanup, namespace renames) that don't require live cluster verification.
