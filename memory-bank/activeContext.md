# Active Context – k3d-manager

## Current Branch: `feature/infra-cluster-complete` (as of 2026-03-01)

**v0.4.0 merged** — ArgoCD Phase 1 complete. ArgoCD deployed live to infra cluster.

---

## Current Focus

v0.5.0: Keycloak plugin — **PR #13 open**, all fixes applied, awaiting owner merge.

**Part A (owner action):** ✅ DONE — ArgoCD deployed live, all 7 pods `2/2 Running`, ExternalSecrets synced.

**Part B (Codex):** ✅ DONE — `deploy_keycloak` plugin committed (`7cc0ca9`).

**Part C (Gemini):** ✅ DONE — 7/7 issues confirmed. shellcheck PASS. bats 6/6.

**Part D (Codex):** ✅ DONE — 7 fixes applied (`03fca04`).

**Part E (Gemini/Codex loop):** ✅ DONE
- Round 2: confirmed missing `$KEYCLOAK_LDAP_USERS_DN` whitelist entry. Fixed (`7603000`).
- PR #13 Copilot review (3 issues): non-Vault admin secret, config CLI flag, shared SecretStore. Fixed (`f0e5f44`).
- YAML password quoting in `_keycloak_ensure_admin_secret`. Fixed (`f81dcd4`).

**All checks green:** shellcheck PASS, bats 6/6, CI PASS (lint + stage2), GitGuardian PASS.

---

## PR #13 — Status

**URL:** https://github.com/wilddog64/k3d-manager/pull/13
**Branch:** `feature/infra-cluster-complete` → `main`
**CI:** ✅ All green
**Copilot review:** ✅ All issues addressed
**Awaiting:** Owner merge

### Commit history (branch vs main)

| Commit | Description |
|---|---|
| `7cc0ca9` | feat(keycloak): add deploy_keycloak plugin |
| `03fca04` | fix(keycloak): address 7 review findings |
| `7603000` | fix(keycloak): add LDAP_USERS_DN to envsubst whitelist |
| `f0e5f44` | fix(keycloak): cover non-vault installs (3 Copilot P1/P2 fixes) |
| `f81dcd4` | fix(keycloak): quote generated admin password in heredoc |
| `b68a8b2` | chore: add v0.5.0 changelog |

---

## Cluster State (as of 2026-03-01)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)

| Component | Status | Notes |
|---|---|---|
| Vault | ✅ Running | `secrets` ns, initialized + unsealed |
| ESO | ✅ Running | `secrets` ns |
| OpenLDAP | ✅ Running | `identity` ns |
| Istio | ✅ Running | `istio-system` |
| Jenkins | ✅ Running | `cicd` ns — smoke test passed (v0.3.1) |
| ArgoCD | ✅ Running | `cicd` ns — deployed (v0.4.0) |
| Keycloak | ❌ Not deployed | `deploy_keycloak` ready — deploy after PR #13 merges |

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

## Release Strategy

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.3.1 | ✅ released | See CHANGE.md |
| v0.4.0 | ✅ merged 2026-03-02 | ArgoCD Phase 1 |
| v0.5.0 | 🔄 PR #13 open | Keycloak plugin (Bitnami), infra cluster complete |
| v0.6.0 | future | Keycloak provider interface (Bitnami + Operator) |

---

## Codex Fix Task — Keycloak Image Pull Failure (Active)

**Branch:** `fix/keycloak-image-fix-task`
**Status:** Pending Codex

### Issue — P1: Bitnami images no longer published on Docker Hub

Live deploy failed with `ImagePullBackOff` on all 3 pods (keycloak-0,
keycloak-postgresql-0, keycloak-keycloak-config-cli). Root cause: Bitnami
stopped publishing images to Docker Hub (free tier) in late 2024. **Pinning
a chart version will not fix this** — `docker.io/bitnami/keycloak:<any-tag>`
returns "no such manifest" regardless of version.

The free alternative is **GitHub Container Registry**:
`ghcr.io/bitnami/keycloak` — images are published there.

### Fix

**File:** `scripts/etc/keycloak/values.yaml.tmpl`

Override the image registry for all 3 images to `ghcr.io`:

```yaml
image:
  registry: ghcr.io

keycloakConfigCli:
  image:
    registry: ghcr.io

postgresql:
  image:
    registry: ghcr.io
```

**Before doing this, Codex must verify the images exist on ghcr.io:**

```bash
docker manifest inspect ghcr.io/bitnami/keycloak:latest
docker manifest inspect ghcr.io/bitnami/postgresql:latest
```

If `ghcr.io` does not have the images, check `helm show values bitnami/keycloak`
for the chart's recommended registry override.

### Also add: `test_keycloak` smoke test

No end-to-end smoke test exists for Keycloak. Add `test_keycloak` command
(modelled after `test_vault`/`test_eso`) to `scripts/plugins/keycloak.sh`:

Minimum checks:
1. `keycloak-0` pod is `2/2 Running` (with Istio sidecar)
2. `keycloak-admin-secret` exists and has a non-empty password key
3. HTTP 200 from `http://keycloak.identity.svc.cluster.local:8080/realms/master`
   (via `kubectl exec` in a curl pod or via port-forward)
4. ExternalSecrets `keycloak-admin-secret` + `keycloak-ldap-secret` are `Ready`

### Verification — Codex MUST run all three steps in order

**Step 1 — Static checks:**
```bash
shellcheck scripts/plugins/keycloak.sh
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/keycloak.bats
```

**Step 2 — Live deploy (required, not optional):**
```bash
./scripts/k3d-manager deploy_keycloak --enable-ldap --enable-vault
```

Codex must confirm:
- All 3 pods reach Running: `keycloak-0`, `keycloak-postgresql-0`, `keycloak-keycloak-config-cli` (Job completes)
- No `ImagePullBackOff` — pinned chart version resolves to a real image
- Helm install exits 0

**Step 3 — End-to-end smoke test:**
```bash
./scripts/k3d-manager test_keycloak
```

All checks in `test_keycloak` must pass before committing. Report exact
output of all three steps in the commit message or memory bank update.
Do NOT commit if the live deploy or smoke test fails.

---

## Open Items

- [x] Owner merges PR #13 → v0.5.0 ✅
- [ ] Keycloak image pin fix + `test_keycloak` smoke test (Codex — `fix/keycloak-image-pin`)
- [ ] Keycloak live deploy — owner runs `deploy_keycloak --enable-ldap --enable-vault` after image fix
- [ ] `configure_vault_app_auth` — `feature/app-cluster-deploy` (Codex)
- [ ] App layer deploy on Ubuntu (Gemini — SSH interactive)
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
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods (ArgoCD redis-init workaround: `pilot-agent request POST 'quitquitquit'`)

---

## Agent Workflow (canonical)

```
Claude
  └── monitors CI / reviews Gemini reports for accuracy
  └── opens PR on owner go-ahead
  └── when CI fails: identifies root cause → writes bug report → hands to Gemini
  └── can write Codex task blocks for logic bugs that don't need cluster verification

Gemini
  └── receives bug report from Claude
  └── verifies root cause (runs tests locally)
  └── writes Codex fix spec; updates memory-bank
  └── handles Ubuntu SSH deployment (interactive)

Codex
  └── reads memory-bank Codex task block
  └── implements fix, commits, pushes
  └── does NOT open PRs

Owner
  └── approves PR
```

**Lesson learned (2026-03-01):** Route bug reports through Gemini before Codex unless
the fix is pure logic with no cluster dependency.
