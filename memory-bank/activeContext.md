# Active Context – k3d-manager

## Current Branch: `feature/two-cluster-infra` (as of 2026-03-01)

**v0.2.1 released** — OrbStack validated, Vault reboot unseal, Jenkins k8s agents, docs.
**v0.3.0 pending** — Two-cluster refactor (this branch) ready for PR.

---

## ⚠️ Codex — ONE Task (read this first)

**Branch:** `feature/two-cluster-infra`
**PR open:** https://github.com/wilddog64/k3d-manager/pull/8 — `lint` CI is FAILING

**Fix ONLY this file:**
`scripts/tests/lib/test_auth_cleanup.bats` — test 53 "test_jenkins trap removes auth file"

**Root cause (do NOT guess — this is exact):**

`VAULT_NS_DEFAULT` changed `vault` → `secrets` in vault.sh. Inside `test_jenkins`, when
`VAULT_NS` is unset, it falls through to `VAULT_NS_DEFAULT` ("secrets") and sets
`vault_release = VAULT_NS = "secrets"` → `vault_pod = "secrets-0"`.

The `_kubectl` mock in the test independently computes `expected_pod` from
`VAULT_RELEASE_DEFAULT` ("vault") → `expected_pod = "vault-0"`.

Mismatch: test calls `exec secrets-0` but mock matches `exec vault-0` only.
→ mock returns empty → `policies=""` → `_err` called → `_err` undefined → exit 127.

**The fix:**
In `test_auth_cleanup.bats`, around line 205, add `VAULT_NS=vault VAULT_RELEASE=vault`
to the `run env ...` call so the test is isolated from the changed default:

```bash
run env PROJECT_ROOT="$PROJECT_ROOT" \
  VAULT_NS=vault VAULT_RELEASE=vault \
  JENKINS_VALUES_FILE="$PROJECT_ROOT/scripts/etc/jenkins/values-test.yaml" \
  CLEANUP_LOG="$cleanup_log" AUTH_PATH_LOG="$auth_path_log" \
  DEPLOY_LOG="$deploy_log" DEPLOY_NS_LOG="$deploy_ns_log" \
  "$script"
```

Apply the same fix to ALL subsequent `run env ...` invocations of `"$script"` in
the same test that don't already set `VAULT_RELEASE` explicitly (to keep them
consistent). Check the full test for other `run env` calls.

**After fixing:** commit to `feature/two-cluster-infra`, push. Claude monitors CI.
**Do NOT touch any other files.**

---

## Current Focus (as of 2026-03-01)

- **Two-cluster refactor COMPLETE** — namespace renames + CLUSTER_ROLE + remote Vault ESO
- PR #8 open — lint failing (test_auth_cleanup regression, see above — Codex fix pending)
- After merge: destroy infra cluster → redeploy with new namespaces → deploy app layer on Ubuntu

---

## Cluster State (as of 2026-03-01)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-test-orbstack-exists`)
| Component | Status | Notes |
|---|---|---|
| Vault | ✅ Running | 4d — will be redeployed to `secrets` ns after PR merge |
| ESO | ✅ Running | 4d — will move to `secrets` ns |
| Jenkins | ✅ Running | — will move to `cicd` ns |
| OpenLDAP | ✅ Running | — will move to `identity` ns |
| Istio | ✅ Running | stays `istio-system` |
| ArgoCD | ❌ Not deployed | add during infra redeploy |
| Keycloak | ❌ Not deployed | add during infra redeploy |

Context `k3d-automation` is dead (old cluster, port gone — ignore).

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`, host: 10.211.55.14)
| Component | Status | Notes |
|---|---|---|
| k3s node | ✅ Ready | Fresh redeploy 2026-02-28, v1.34.4+k3s1 |
| Istio | ✅ Running | IngressGateway + istiod |
| ESO | ❌ Pending | Deploy after PR merge with `REMOTE_VAULT_ADDR` |
| shopping-cart-data | ❌ Pending | PostgreSQL, Redis, RabbitMQ |
| shopping-cart-apps | ❌ Pending | basket, order, payment, catalog, frontend |
| observability | ❌ Pending | Prometheus + Grafana |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. If git auth fails: `ssh -O exit ubuntu` to kill stale ControlMaster.

---

## What Changed in This PR (feature/two-cluster-infra)

### Namespace renames (new defaults, env var overrides preserved)
| Old | New | Var |
|---|---|---|
| `vault` + `external-secrets` | `secrets` | `VAULT_NS`, `ESO_NAMESPACE` |
| `jenkins` | `cicd` | `JENKINS_NAMESPACE` |
| `directory` | `identity` | `LDAP_NAMESPACE` |
| `argocd` | `cicd` | `ARGOCD_NAMESPACE` |

### New capabilities
- `CLUSTER_ROLE=infra|app` in dispatcher — `app` skips Vault/Jenkins/LDAP/ArgoCD
- `_eso_configure_remote_vault` in `scripts/plugins/eso.sh` — cross-cluster SecretStore
- `REMOTE_VAULT_ADDR` + `REMOTE_VAULT_K8S_MOUNT` + `REMOTE_VAULT_K8S_ROLE` env vars
- `VAULT_ENDPOINT` now dynamic: `http://vault.${VAULT_NS}.svc:8200`
- `ARGOCD_LDAP_HOST` + `JENKINS_LDAP_HOST` updated to `identity` namespace

### Hardcoded namespace strings fixed
- `scripts/lib/test.sh` — `-n jenkins`, `-n vault` → env var refs
- `scripts/ci/check_cluster_health.sh` — `namespace="${1:-vault}"` → `${VAULT_NS:-secrets}`
- `scripts/tests/run-cert-rotation-test.sh` — `-n jenkins` → env var
- `scripts/lib/dirservices/openldap.sh` — `directory` default → `identity`

---

## Post-Merge Deployment Plan (Claude executes)

```
1. Destroy infra cluster (k3d-k3d-test-orbstack-exists)
2. Redeploy: CLUSTER_NAME=automation CLUSTER_ROLE=infra
   → secrets/   (Vault + ESO)
   → identity/  (OpenLDAP + Keycloak)
   → cicd/      (Jenkins + ArgoCD)
   → istio-system/
3. Configure Vault kubernetes-app auth mount for app cluster
4. Deploy app layer: CLUSTER_ROLE=app REMOTE_VAULT_ADDR=https://10.211.55.3:8200
   → ESO → shopping-cart-data → shopping-cart-apps
```

---

## Open Items (post-merge)

- [ ] ArgoCD deploy on infra cluster (cicd ns)
- [ ] Keycloak deploy on infra cluster (identity ns)
- [ ] App layer deploy on Ubuntu (ESO + data + apps)
- [ ] Wire ArgoCD to sync app cluster
- [ ] Cloud Track A: Terraform + k3s on EC2 (blocked on two-cluster done)
- [ ] Cloud Track 0: one-node EKS provider development

---

## Known Broken Paths (all pre-existing)
| Path | Root Cause |
|---|---|
| `deploy_jenkins` (no vault) | Policy creation always runs; jenkins-admin secret missing |
| `--enable-ldap` without `--enable-vault` | LDAP secrets require Vault |
| Basic LDAP deploys empty directory | No bootstrap LDIF; use `deploy_ad` as workaround |

---

## Release Strategy

| Version | Status | Notes |
|---|---|---|
| v0.1.0 | ✅ released 2026-02-27 | Initial release |
| v0.2.0 | ✅ released 2026-02-27 | OrbStack, Vault reboot unseal, Jenkins k8s agents |
| v0.2.1 | ✅ released 2026-02-28 | Docs-only: CHANGE.md + README Releases table |
| v0.3.0 | pending PR | Two-cluster refactor, namespace renames, CLUSTER_ROLE, remote Vault ESO |
| v1.0.0 | future | Production-hardened, all known-broken paths resolved |

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **LDAP bind DN**: keep `LDAP_BASE_DN` in sync with LDIF bootstrap base DN
- **Jenkins admin password**: contains special chars — always quote `-u "user:$pass"`
- **SMB CSI on macOS**: `cifs` kernel module unavailable — skip guard active
- **Vault reboot unseal**: dual-path — macOS Keychain + Linux libsecret; k8s `vault-unseal` secret is fallback
- **Ubuntu SSH agent forwarding**: `ForwardAgent yes` set. Stale socket fix: `ssh -O exit ubuntu`
- **New namespace defaults**: `secrets`, `identity`, `cicd` — old names still work via env var override

---

## Branch Protection

- 1 required PR approval, stale review dismissal, enforce admins disabled
- Required status checks: `lint` (Stage 1) and `stage2` (Stage 2)
- Tag: `@copilot` in PR body for automated review
