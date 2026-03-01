# Active Context – k3d-manager

## Current Branch: `feature/two-cluster-infra` (as of 2026-03-01)

**v0.2.1 released** — OrbStack validated, Vault reboot unseal, Jenkins k8s agents, docs.
**v0.3.0 pending** — Two-cluster refactor (this branch) ready for PR.

---

## ✅ Codex — Latest Updates (2026-03-02)

- **P1 cleanup trap fixed:** `_cleanup_cert_rotation_test` now references
  `${JENKINS_NAMESPACE:-cicd}` directly, so the EXIT trap no longer reads the
  out-of-scope `jenkins_ns` local. (File: `scripts/lib/test.sh` lines 1058–1063)
- **P2 remote SecretStore fix:** `deploy_eso` now passes the resolved `$ns`
  argument into `_eso_configure_remote_vault` when
  `ESO_REMOTE_SERVICE_ACCOUNT_NAMESPACE` is unset, so remote Vault
  configurations with custom namespaces point at the right service account.
  (File: `scripts/plugins/eso.sh` lines 97–103)
- **Tests:** `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/eso.bats`
  ✅ — ensures the ESO plugin regressions stay covered.

No further Codex tasks are pending on PR #8 as of this update.

---

## ✅ test_auth_cleanup.bats — FIXED (2026-03-02)

**PR #8:** `lint` CI is now **PASSING** (commit `4ab40ad`).

Root cause: Codex added `VAULT_NS=vault VAULT_RELEASE=vault` to ALL sub-calls.
`VAULT_RELEASE=vault` pinned vault_release via derivation branch-1, breaking
assertions like "user-default", "vault-derived", etc.

Fix applied by Claude: removed `VAULT_NS=vault VAULT_RELEASE=vault` from all
7 sub-calls. Only the first `run env` call (line 205) keeps `VAULT_NS=vault`
to satisfy the `VAULT_NS_DEFAULT=secrets` change in vault.sh.

---

## ⚠️ Security Notice (2026-02-28)

**GitGuardian: 1 internal secret incident detected (reported 4:27 PM PST)**
- Full analysis: `docs/issues/2026-02-28-gitguardian-internal-ip-addresses-in-docs.md`
- **No credentials, tokens, or keys were committed** — severity: LOW
- Likely trigger: internal IP addresses (`10.211.55.x`) committed in docs/plans and memory-bank,
  OR example AWS IP `54.210.1.50` in `cloud-architecture.md`
- **Action required (owner):** Open GitGuardian dashboard → mark incident as false positive
- Going forward: use `<MAC-IP>`, `<UBUNTU-IP>`, `<NODE-IP>` in docs instead of real IPs

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

Codex
  └── reads memory-bank Codex task block (written by Gemini)
  └── implements fix, commits, pushes
  └── does NOT open PRs

Owner
  └── approves PR
```

**Lesson learned (2026-03-01):** Claude wrote Codex fix instructions directly,
which caused Codex to apply an over-broad fix (VAULT_RELEASE=vault on all calls
instead of just the first). Bug reports should always go through Gemini for
verification before Codex gets a fix spec.
