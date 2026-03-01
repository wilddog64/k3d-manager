# Active Context – k3d-manager

## Current Branch: `feature/infra-cluster-complete` (as of 2026-03-01)

**v0.4.0 merged** — ArgoCD Phase 1 complete. ArgoCD deployed live to infra cluster.

---

## Current Focus

v0.5.0: Complete infra cluster layer.

**Part A (owner action):** ✅ DONE — ArgoCD deployed live, all 7 pods `2/2 Running`,
ExternalSecrets synced.

**Part B (Codex):** ✅ DONE — `deploy_keycloak` plugin committed (`7cc0ca9`).

**Part C (Gemini):** ✅ DONE — 7/7 issues confirmed. shellcheck PASS. bats 6/6.

**Part D (Codex):** ✅ DONE — 7 fixes applied (commit `03fca04`).

**Part E (Gemini):** Round 2 confirmed missing `$KEYCLOAK_LDAP_USERS_DN` whitelist entry. Codex added it and reran tests (`shellcheck`, `bats scripts/tests/plugins/keycloak.bats`).

**2026-03-03 Update (Codex):**
- Added `scripts/plugins/keycloak.sh` with `deploy_keycloak`, Vault/ESO helpers,
  and realm config management.
- Created full template set under `scripts/etc/keycloak/` (values, secretstore,
  ExternalSecrets, realm JSON, VirtualService, vars file).
- New `scripts/tests/plugins/keycloak.bats` (6 cases) validates help text,
  namespace defaults, CLUSTER_ROLE guard, flag errors, and helper availability.
- Tests run: `shellcheck scripts/plugins/keycloak.sh`,
  `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/keycloak.bats` ✅

**2026-03-01 Update (Claude review):**
- Claude reviewed all Keycloak files — 7 issues found (3 P1, 2 P2, 1 P3, 1 minor).
- Gemini verification spec written to `docs/plans/keycloak-gemini-verification.md`.
- Gemini to confirm issues and write Codex fix spec before PR.

---

## Gemini Task — Keycloak Plugin Verification (Complete 2026-03-02) ✅

**Branch:** `feature/infra-cluster-complete`
**Status:** Verified ✅ — **All 7 suspected issues CONFIRMED**

### Verification Results

1. **Mechanical Checks:** **PASSED** ✅
   - `shellcheck scripts/plugins/keycloak.sh`: Clean.
   - `bats scripts/tests/plugins/keycloak.bats`: 6/6 tests passed.

2. **Issue Confirmation:** **ALL CONFIRMED** 🔴
   - Issue 1: `_keycloak_apply_realm_configmap` is indeed called unconditionally.
   - Issue 2: `VAULT_VARS_FILE` is missing from the header.
   - Issue 3: `realm-config.json.tmpl` uses key names (`LDAP_BIND_DN`) instead of actual values.
   - Issue 4: Uses legacy `userFederationProviders` (deprecated since KC 17).
   - Issue 5: `KEYCLOAK_USER` mapped to the password secret key.
   - Issue 6: `KEYCLOAK_IMPORT` conflicts with `keycloakConfigCli`.
   - Issue 7: VirtualService has hardcoded namespace and gateway.

---

## Codex Fix Task — Keycloak Plugin (COMPLETE ✅)

**Branch:** `feature/infra-cluster-complete`
**Spec:** `docs/plans/keycloak-codex-fixes.md`
**Commit:** `03fca04`
**Status:** All 7 fixes applied and verified (shellcheck PASS, bats 6/6)

---

## Gemini Task — Keycloak Plugin Verification Round 2 (Complete 2026-03-03) ✅

**Branch:** `feature/infra-cluster-complete`
**Status:** Verified ✅ — **1 minor fix required**

### Verification Results

1. **Mechanical Checks:** **PASSED** ✅
   - `shellcheck scripts/plugins/keycloak.sh`: Clean.
   - `bats scripts/tests/plugins/keycloak.bats`: 6/6 tests passed.

2. **Step 2 (envsubst whitelist):** **ISSUE CONFIRMED** 🔴
   - `KEYCLOAK_LDAP_USERS_DN` is missing from the whitelist at line 212 of `keycloak.sh`.

3. **Step 3 (uid vs cn):** **uid IS CORRECT** ✅
   - Evidence from `jenkins-users-groups.ldif` confirms `uid` is standard for `inetOrgPerson`.

4. **Step 4 (static id safety):** **SAFE** ✅
   - Stable ID ensures idempotency for `keycloak-config-cli`.

### Next Steps for Codex

Codex must add `$KEYCLOAK_LDAP_USERS_DN` to the `envsubst` whitelist in `scripts/plugins/keycloak.sh` (line 212). Fix spec documented in `docs/plans/keycloak-gemini-verification-2.md`.

---

## Codex Task — Keycloak Plugin (COMPLETE ✅)

**Commit:** `7cc0ca9`
**Files created:**
| `scripts/etc/keycloak/externalsecret-ldap.yaml.tmpl` | LDAP bind password ESO |
| `scripts/etc/keycloak/realm-config.json.tmpl` | Realm JSON with LDAP federation |
| `scripts/etc/keycloak/virtualservice.yaml.tmpl` | Istio VirtualService |
| `scripts/tests/plugins/keycloak.bats` | Bats suite (min 6 cases) |

### Verification Codex must run

```bash
shellcheck scripts/plugins/keycloak.sh
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/keycloak.bats
```

---

## ArgoCD History

**2026-03-02 Update:**
- `projects/platform.yaml` converted to `platform.yaml.tmpl` with
  `${ARGOCD_NAMESPACE}` substitution. `_argocd_deploy_appproject` now renders via
  `envsubst` before applying.
- `applicationsets/{platform-helm,services-git,demo-rollout}.yaml` cleaned of
  cluster metadata, set to the new `cicd` namespace, and repo URLs updated to
  `wilddog64/k3d-manager`.
- Added `_argocd_seed_vault_admin_secret` so Vault always contains the
  `${ARGOCD_VAULT_KV_MOUNT}/${ARGOCD_ADMIN_VAULT_PATH}` entry when
  `--enable-vault` is used.
- New `scripts/tests/plugins/argocd.bats` suite covers help text, namespace
  defaults, CLUSTER_ROLE guard, skip logic, and missing-template errors.
- Tests: `shellcheck scripts/plugins/argocd.sh`,
  `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/argocd.bats` ✅

**2026-03-03 Review Fixes:**
- `_argocd_seed_vault_admin_secret` now checks the exit code of `vault kv put`
  and fails fast if Vault writes do not succeed.
- All ApplicationSet manifests parameterize `metadata.namespace` via
  `${ARGOCD_NAMESPACE}` and `_argocd_deploy_applicationsets` renders them with
  `envsubst` before applying.

**Codex task spec:** `docs/plans/argocd-phase1-codex-task.md`

---

## Gemini Verification Task — ArgoCD Phase 1 (Complete 2026-03-02) ✅

**Branch:** `feature/argocd-phase1`
**Commit verified:** `aed5e68`
**Status:** Verified ✅

### Results:

1. **Code Verification:** **PASSED** ✅
   - `platform.yaml.tmpl` correctly uses `${ARGOCD_NAMESPACE}` and updated destinations.
   - ApplicationSet manifests cleaned of metadata and correctly target `cicd` / `wilddog64`.
   - `_argocd_deploy_appproject` correctly uses `envsubst` with variable whitelist.
   - `_argocd_seed_vault_admin_secret` correctly seeds random password if missing.
2. **Shellcheck:** **PASSED** ✅. `scripts/plugins/argocd.sh` is clean.
3. **Bats Tests:** **PASSED** ✅. `scripts/tests/plugins/argocd.bats` passed 6/6.
4. **Sanity Checks:** **PASSED** ✅. Verified defaults and strings in all modified manifests.

**Notes on minor issue:** The redundant `trap ... RETURN` in `_argocd_deploy_appproject` is harmless and matches patterns found in other recently fixed plugins (like `jenkins.sh`). Accepted as-is to maintain local consistency.

**Sign-off:** Phase 1 implementation is complete, verified, and logically sound. Ready for PR.

---

## Codex Fix Task — PR #11 Copilot Review (Active)

**Branch:** `feature/argocd-phase1`
**Source:** Copilot review on PR #11, commit `5223ecb`
**Status:** Pending Codex fix

### Fix 1 — P1: Check Vault write exit code in `_argocd_seed_vault_admin_secret`

**File:** `scripts/plugins/argocd.sh`

The `_vault_exec_stream ... vault kv put` call result is currently ignored.
If it fails (Vault sealed, bad auth, wrong mount), the function logs success
and `deploy_argocd` continues — leaving the ExternalSecret pointing at a
non-existent secret path.

**Change:**
```bash
# Before (current):
   _vault_login "$ns" "$release"
   _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
      vault kv put "$secret_path" "${ARGOCD_ADMIN_PASSWORD_KEY}=${password}"

   _info "[argocd] ArgoCD admin password seeded. Retrieve via Kubernetes secret after ESO sync"

# After:
   _vault_login "$ns" "$release"
   local rc=0
   _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
      vault kv put "$secret_path" "${ARGOCD_ADMIN_PASSWORD_KEY}=${password}" || rc=$?
   if (( rc != 0 )); then
      _err "[argocd] Failed to seed admin password in Vault (exit code $rc). Check Vault status and auth."
      return "$rc"
   fi

   _info "[argocd] ArgoCD admin password seeded. Retrieve via Kubernetes secret after ESO sync"
```

### Fix 2 — P2: Parameterize ApplicationSet `metadata.namespace`

**Files:**
- `scripts/etc/argocd/applicationsets/platform-helm.yaml`
- `scripts/etc/argocd/applicationsets/services-git.yaml`
- `scripts/etc/argocd/applicationsets/demo-rollout.yaml`
- `scripts/plugins/argocd.sh` — `_argocd_deploy_applicationsets`

The `metadata.namespace: cicd` is hardcoded in all three YAML files.
When `ARGOCD_NAMESPACE` is overridden, the ApplicationSets land in the
wrong namespace.

**Step A — update all three YAML files:**
Change `namespace: cicd` (in `metadata` only, not in template `destination`)
to `namespace: ${ARGOCD_NAMESPACE}`.

Note: these files contain Go template syntax (`{{.name}}` etc.) — envsubst
is safe because it only replaces `$VAR`/`${VAR}` patterns, not `{{...}}`.

**Step B — update `_argocd_deploy_applicationsets` to render via envsubst:**
```bash
# Before (current):
      if _kubectl apply -f "$file" >/dev/null 2>&1; then

# After:
      if envsubst '$ARGOCD_NAMESPACE' < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
```

### Verification Codex must run

```bash
shellcheck scripts/plugins/argocd.sh
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/argocd.bats
```

Both must pass before committing. Codex to push to `feature/argocd-phase1`.

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
| ArgoCD | ✅ Running | `cicd` ns — deployed (v0.4.0) |
| Keycloak | ❌ Not deployed | `deploy_keycloak` pending Codex (`feature/infra-cluster-complete`) |

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
| v0.4.0 | ✅ merged 2026-03-02 | ArgoCD Phase 1 |
| v0.5.0 | future | Keycloak plugin (Bitnami), infra cluster complete |
| v0.6.0 | future | Keycloak provider interface (Bitnami + Operator) |

---

## Open Items (post v0.4.0)

- [ ] ArgoCD live deploy — owner runs `deploy_argocd --enable-ldap --enable-vault --bootstrap` (Part A)
- [ ] Keycloak plugin — `feature/infra-cluster-complete` (Codex — Part B)
- [ ] App layer deploy on Ubuntu (Gemini — SSH interactive)
- [ ] `configure_vault_app_auth` — `feature/app-cluster-deploy` (Codex)
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
