# Active Context – k3d-manager

## Current Branch: `fix/jenkins-cicd-namespace` (as of 2026-03-01)

**v0.3.0 merged** — Two-cluster refactor, namespace renames, CLUSTER_ROLE, remote Vault ESO.

---

## Current Focus

`fix/jenkins-cicd-namespace` branch ensures Jenkins honors the `cicd` namespace.

**2026-03-02 Update:**
- `scripts/etc/jenkins/jenkins-home-pv.yaml.tmpl` now emits `$JENKINS_NAMESPACE`, and
  `_create_jenkins_pv_pvc` exports the namespace before calling `envsubst`.
- `deploy_jenkins` defaults to `${JENKINS_NAMESPACE:-jenkins}` when the CLI flag is
  omitted, so env overrides take effect.
- Tests: `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/lib/test_auth_cleanup.bats`
  ✅, `shellcheck scripts/plugins/jenkins.sh` ✅. Attempting
  `bats scripts/tests/plugins/jenkins.bats` fails because the file does not exist in
  `scripts/tests/plugins/` (no Jenkins-specific suite yet).

---

## Codex Task — Jenkins `cicd` Namespace Fix

**Branch:** `fix/jenkins-cicd-namespace`
**Plan:** `docs/plans/jenkins-cicd-namespace-fix.md`
**Issues:** `docs/issues/2026-03-01-jenkins-pv-template-hardcoded-namespace.md` (P2)
           `docs/issues/2026-03-01-deploy-jenkins-ignores-jenkins-namespace-env-var.md` (P3)

### Exact changes required (3 total)

**Change 1 — `scripts/etc/jenkins/jenkins-home-pv.yaml.tmpl` line 13:**
```yaml
# Before:
  namespace: jenkins
# After:
  namespace: $JENKINS_NAMESPACE
```

**Change 2 — `scripts/plugins/jenkins.sh` inside `_create_jenkins_pv_pvc` (~line 456):**
Add `export JENKINS_NAMESPACE="$jenkins_namespace"` immediately before the `envsubst` call:
```bash
   # BEFORE envsubst line:
   export JENKINS_NAMESPACE="$jenkins_namespace"
   envsubst < "$jenkins_pv_template" > "$jenkinsyamfile"
```

**Change 3 — `scripts/plugins/jenkins.sh` line 1281:**
```bash
# Before:
jenkins_namespace="${jenkins_namespace:-jenkins}"
# After:
jenkins_namespace="${jenkins_namespace:-${JENKINS_NAMESPACE:-jenkins}}"
```

### What NOT to change

- `vault-seed-wrapper.yaml` — not auto-deployed, skip it
- No new bats tests needed — run existing tests to verify no regression

### After implementing, run:
```bash
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/jenkins.bats
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/lib/test_auth_cleanup.bats
shellcheck scripts/plugins/jenkins.sh
```

### Commit message:
```
fix(jenkins): allow deploy_jenkins to target any namespace

- jenkins-home-pv.yaml.tmpl: use $JENKINS_NAMESPACE instead of hardcoded "jenkins"
- _create_jenkins_pv_pvc: export JENKINS_NAMESPACE before envsubst
- deploy_jenkins line 1281: fall back to $JENKINS_NAMESPACE env var

Fixes: deploy_jenkins --namespace cicd failing with namespace mismatch error.
```

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
| Jenkins | ❌ Blocked | PV template has hardcoded `namespace: jenkins` — P2 bug |
| ArgoCD | ❌ Not deployed | no `deploy_argocd` command yet |
| Keycloak | ❌ Not deployed | no `deploy_keycloak` command yet |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`, host: `<UBUNTU-IP>`)
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

### Bug fixes (post-review)
- `deploy_vault`: `ns` now `${VAULT_NS:-$VAULT_NS_DEFAULT}` — respects `VAULT_NS` override
- `_cleanup_cert_rotation_test`: uses `${JENKINS_NAMESPACE:-cicd}` directly, not out-of-scope local
- `deploy_eso` remote SecretStore: passes `$ns` instead of `${ESO_NAMESPACE:-secrets}`

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
4. Deploy app layer: CLUSTER_ROLE=app REMOTE_VAULT_ADDR=https://<MAC-IP>:8200
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
- [ ] GitGuardian dashboard: mark 2026-02-28 incident as false positive (owner action)

---

## Known Broken Paths

### Pre-existing
| Path | Root Cause |
|---|---|
| `deploy_jenkins` (no vault) | Policy creation always runs; jenkins-admin secret missing |
| `--enable-ldap` without `--enable-vault` | LDAP secrets require Vault |
| Basic LDAP deploys empty directory | No bootstrap LDIF; use `deploy_ad` as workaround |

### New (found during v0.3.0 rebuild — 2026-03-01)
| Path | Root Cause | Severity | Doc |
|---|---|---|---|
| `CLUSTER_NAME=automation` ignored | Cluster created as `k3d-cluster`; env var not picked up in provider | P3 | `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md` |
| `deploy_jenkins --namespace cicd` fails at PV/PVC | `jenkins-home-pv.yaml.tmpl` has `namespace: jenkins` hardcoded | P2 | `docs/issues/2026-03-01-jenkins-pv-template-hardcoded-namespace.md` |
| `JENKINS_NAMESPACE=cicd deploy_jenkins` ignored | Line 1281 defaults to `"jenkins"` literal, not `${JENKINS_NAMESPACE:-jenkins}` | P3 | `docs/issues/2026-03-01-deploy-jenkins-ignores-jenkins-namespace-env-var.md` |

---

## Release Strategy

| Version | Status | Notes |
|---|---|---|
| v0.1.0 | ✅ released 2026-02-27 | Initial release |
| v0.2.0 | ✅ released 2026-02-27 | OrbStack, Vault reboot unseal, Jenkins k8s agents |
| v0.2.1 | ✅ released 2026-02-28 | Docs-only: CHANGE.md + README Releases table |
| v0.3.0 | ✅ merged 2026-03-01 | Two-cluster refactor, namespace renames, CLUSTER_ROLE, remote Vault ESO |
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
which caused Codex to apply an over-broad fix. Bug reports should always go
through Gemini for verification before Codex gets a fix spec.
