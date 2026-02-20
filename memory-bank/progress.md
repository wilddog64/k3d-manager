# Progress – k3d-manager

## Overall Status

Branch `ldap-develop` is in the **final validation phase** of the AD integration
milestone. Core code is complete; remaining work is testing and documentation.

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

### Vault & Secrets
- [x] Vault deployment via Helm with auto-init and unseal
- [x] Vault PKI bootstrap (root CA + issuing role for jenkins-tls)
- [x] Vault K8s auth method setup for ESO integration
- [x] ESO deployment + SecretStore wiring to Vault
- [x] `reunseal_vault` helper (Keychain/libsecret shard retrieval)
- [x] Secret backend abstraction (`SECRET_BACKEND` env var, `vault` backend complete)

### Jenkins
- [x] Jenkins deployment via Helm with Vault-issued TLS cert
- [x] ExternalSecret resources for Jenkins credentials via ESO
- [x] Jenkins cert rotation CronJob (`jenkins-cert-rotator`) — code complete
- [x] JCasC authorization in flat `permissions:` format (matrix-auth plugin safe)
- [x] `bin/smoke-test-jenkins.sh` Phases 1–3 (SSL + basic auth)

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
- [x] `docs/issues/` — three resolved issues documented

---

## What Is Pending ⏳

### Priority 1 (Must complete before merge to main)

- [ ] **Certificate Rotation Validation** — run full test plan on Ubuntu/k3s
  - Test plan: `docs/tests/certificate-rotation-validation.md`
  - 8 test cases: deploy → wait → trigger → verify rotation → verify revocation → continuity
  - Short-TTL config (10m cert, 5m threshold, 2min CronJob)
  - Status: READY TO EXECUTE. Requires Ubuntu/k3s environment.

- [ ] **End-to-End AD Integration Test** — validate both AD modes
  - `--enable-ad` (OpenLDAP + AD schema): deploy, login as alice/bob/charlie, verify group mapping
  - `--enable-ad-prod` (real AD): requires access to AD environment
  - Guide: `docs/tests/active-directory-testing-instructions.md`

### Priority 2 (Documentation — complete before or shortly after merge)

- [ ] `docs/guides/certificate-rotation.md` — operator guide for cert rotation
- [ ] `docs/guides/mac-ad-setup.md` — macOS AD connectivity setup
- [ ] `docs/guides/ad-connectivity-troubleshooting.md` — AD debugging guide

### Priority 3 (Nice-to-have / future)

- [ ] `bootstrap-basic-schema.ldif` for standard LDAP with pre-seeded users
- [ ] `--keep-test-users` flag for `deploy_ldap`
- [ ] `bin/smoke-test-jenkins.sh` Phases 4–5 (auth flow, LDAP-specific tests)
- [ ] `test_jenkins_smoke` command in main dispatcher
- [ ] Azure secret backend: complete wiring (`azure` plugin exists, partial)
- [ ] AWS / GCP secret backends (planned in `SECRET_BACKEND` abstraction)
- [ ] Monitoring recommendations (Prometheus alerts for cert expiry)
- [ ] Additional automated Bats tests for Jenkins and ESO plugins

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| `deploy_jenkins` (no vault) broken | OPEN | Policy creation always runs; jenkins-admin secret missing |
| `--enable-ldap` without `--enable-vault` broken | OPEN | LDAP secrets require Vault |
| Basic LDAP deploys empty directory | OPEN | No bootstrap LDIF yet; use `deploy_ad` as workaround |
| Cert rotation untested in live cluster | OPEN | Priority 1 blocker |
| ESO SecretStore `mountPath` wrong | FIXED | Must be `kubernetes` not `auth/kubernetes` |
| LDAP bind DN mismatch | FIXED | Keep `LDAP_BASE_DN` consistent with LDIF base DN |
| Jenkins pod readiness timeout | FIXED | 10m timeout + pod existence check |
