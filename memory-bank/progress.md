# Progress – k3d-manager

## Overall Status

`ldap-develop` merged to `main` via PR #2 (2026-02-27). **v0.1.0 released.**

**Two-Cluster Namespace Refactor — READY FOR PR ✅ (2026-03-01)**
Namespace renames, CLUSTER_ROLE gating, and remote Vault ESO support implemented by Codex.
Verified by Gemini: shellcheck clean, ESO API v1 fixed, regression tests green on m4-air.

---

## What Is Complete ✅

### Core Infrastructure
- [x] Dispatcher + lazy plugin loading pattern (`scripts/k3d-manager`)
- [x] `_run_command` wrapper (sudo probing, trace auto-disable for sensitive flags)
- [x] Configuration-driven strategy pattern (CLUSTER_PROVIDER, DIRECTORY_SERVICE_PROVIDER, SECRET_BACKEND)
- [x] k3d provider implementation (Docker-based, macOS default)
- [x] k3s provider implementation (systemd-based, Linux)
- [x] Bats test framework integration (auto-install via `_ensure_bats`)
- [x] Test log hierarchy (`scratch/test-logs/<suite>/<case-hash>/<timestamp>.log`)
- [x] Test strategy overhaul: removed brittle mock-heavy BATS suites
- [x] Added `test smoke` E2E subcommand in `scripts/lib/help/utils.sh`

### Vault & Secrets
- [x] Vault deployment via Helm with auto-init and unseal
- [x] Vault PKI bootstrap (root CA + issuing role for jenkins-tls)
- [x] Vault K8s auth method setup for ESO integration
- [x] ESO deployment + SecretStore wiring to Vault
- [x] `reunseal_vault` helper (Keychain/libsecret shard retrieval)
- [x] Secret backend abstraction (`SECRET_BACKEND` env var, `vault` backend complete)
- [x] Two-cluster refactor (namespace renames, role gating, remote vault support) — **VERIFIED 2026-03-01**

### Jenkins
- [x] Jenkins deployment via Helm with Vault-issued TLS cert
- [x] ExternalSecret resources for Jenkins credentials via ESO
- [x] Jenkins cert rotation CronJob (`jenkins-cert-rotator`) — code complete
- [x] Jenkins cert rotation auth/template fixes (`envsubst` default handling)
- [x] JCasC authorization in flat `permissions:` format (matrix-auth plugin safe)
- [x] `bin/smoke-test-jenkins.sh` integrated into `test smoke` workflow

### Directory Services
- [x] Directory service provider abstraction (interface contract defined)
- [x] OpenLDAP provider — full implementation
- [x] OpenLDAP with AD-compatible schema (`deploy_ad` command, `bootstrap-ad-schema.ldif`)
- [x] Active Directory provider — all interface functions implemented
- [x] AD provider: 36 automated Bats tests, 100% passing
- [x] `--enable-ad` flag (OpenLDAP + AD schema testing mode)
- [x] `--enable-ad-prod` flag (external real AD via `AD_DOMAIN`)
- [x] `--enable-ldap` flag (standard OpenLDAP)
- [x] `TOKENGROUPS` strategy for efficient real-AD nested group resolution
- [x] `AD_TEST_MODE=1` for offline unit testing

### Documentation & Rules
- [x] CLAUDE.md (comprehensive dev guide)
- [x] `.clinerules` built from docs/ (2026-02-19, covers all known patterns and gotchas)
- [x] `memory-bank/` created (this session, 2026-02-19)
- [x] `docs/tests/certificate-rotation-validation.md` (test plan ready)
- [x] `docs/tests/active-directory-testing-instructions.md`
- [x] `docs/plans/` — full set of interface and integration design docs
- [x] `docs/issues/` updated with operational issues through 2026-02-20
- [x] Vault: `system:auth-delegator` ClusterRoleBinding in `deploy_vault` — code complete and validated via `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_vault` (2026-02-27).

---

## What Is Pending ⏳

### Priority 1 (Current focus)

**Two-Cluster Implementation:**
- [x] k3d-manager app-cluster mode refactor — **VERIFIED 2026-03-01**
- [ ] PR merge to `main` — **READY FOR CLAUDE**
- [ ] Destroy infra cluster → redeploy with new namespaces (secrets/identity/cicd)
- [ ] ESO deploy on App cluster (remote Vault addr: `https://<mac-ip>:8200`)
- [ ] shopping-cart-data / apps deployment on Ubuntu

---

## LinkedIn Article Series (k3d-manager)

Write articles as milestones are reached. Each post builds on the last.

| Part | Status | Topic | Trigger |
|---|---|---|---|
| Part 1 | ✅ Live (1,332 impr.) | Contrarian origin — "Everyone told me to use a real tool" | — |
| Part 2 | ✅ Live (~30 impr., 3AM handicap) | Architecture emerged, wasn't designed | — |
| Part 3 | Pending | Two-cluster problem — why single cluster isn't enough | After PR #8 merged + infra redeployed |
| Part 4 | Pending | Multi-agent workflow — Codex/Gemini/Claude, what actually happened | After two-cluster stable |
| Part 5 | Pending | Taking it to AWS — what changes, what stays identical | After Track A (k3s on EC2) working |
| Part 6 | Pending | Shopping cart runs end-to-end | After full stack deployed |

**Notes:**
- Part 4 (multi-agent) has the broadest reach potential — not just Kubernetes audience
- Schedule posts 7–9 AM Tuesday–Thursday (avoid 3 AM repeats)
- Each part should link back to the previous — compounds impressions on older posts

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| `test_eso` fails — ClusterSecretStore API version mismatch | FIXED | 2026-02-27: `v1beta1` → `v1` in `scripts/lib/test.sh`. |
| `test_eso` fails — `insecureSkipVerify` removed in ESO v1 | FIXED | 2026-03-01: `_eso_configure_remote_vault` fixed by Codex (verified by Gemini). |
| `test_istio` fails — hardcoded namespace `istio-test` | FIXED | 2026-02-27: all references now use `$test_ns`. |
| Vault `system:auth-delegator` missing from `deploy_vault` | FIXED | 2026-02-27: Idempotent binding added to `vault.sh`. |
| shellcheck warnings in refactored code | FIXED | 2026-03-01: All warnings resolved or suppressed with reason (verified by Gemini). |
| GitGuardian: 1 internal secret incident (2026-02-28) | OPEN | No real secrets — likely IPs in docs. Mark false positive in dashboard. See `docs/issues/2026-02-28-gitguardian-internal-ip-addresses-in-docs.md`. |
| `test_auth_cleanup.bats` regression | OPEN | `PATH="/opt/homebrew/bin:$PATH" source scripts/lib/system.sh && export -f _info _warn _err _no_trace && bats scripts/tests/lib/test_auth_cleanup.bats` fails at `[[ "$output" == "user-default" ]]` because `_kubectl` mock now sees `VAULT_RELEASE=vault` and never exercises the default-derivation paths (needs follow-up). |
