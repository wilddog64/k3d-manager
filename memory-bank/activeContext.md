# Active Context – k3d-manager

## Current Branch: `ldap-develop`

This is the active development branch for Active Directory integration and certificate
rotation. It has NOT been merged to `main` yet.

## Session Objective (as of 2026-02-19)

- Build comprehensive `.clinerules` from docs/ (DONE – see `.clinerules`).
- Create memory bank for cross-agent continuity (THIS SESSION).

## What Has Been Built on `ldap-develop`

### Completed Features
- **Active Directory provider** (`scripts/lib/dirservices/activedirectory.sh`)
  - All interface functions implemented.
  - 36 automated Bats tests, 100% passing.
  - Validates connectivity (DNS + LDAP port), never deploys.
  - `TOKENGROUPS` strategy for efficient nested group resolution.
  - `AD_TEST_MODE=1` for offline unit testing.

- **OpenLDAP AD-schema variant** (`deploy_ad` command)
  - Deploys OpenLDAP with `bootstrap-ad-schema.ldif`.
  - Pre-seeded with `alice` (admin), `bob` (developer), `charlie` (read-only).
  - All test users: password = `password`.
  - Used as a local stand-in for real AD during integration testing.

- **Jenkins directory service integration**
  - `--enable-ad` flag: uses OpenLDAP+AD-schema.
  - `--enable-ad-prod` flag: uses real AD (requires `AD_DOMAIN`).
  - `--enable-ldap` flag: uses standard OpenLDAP schema.
  - JCasC generation via `_dirservice_*_generate_jcasc` interface.

- **Certificate rotation CronJob** (`jenkins-cert-rotator`)
  - Code is in place; triggers Vault PKI renewal, updates K8s secret, revokes old cert.
  - CronJob image: `docker.io/google/cloud-sdk:slim`.
  - **Status: NEVER VALIDATED IN A LIVE CLUSTER.**

- **Jenkins smoke test** (`bin/smoke-test-jenkins.sh`)
  - Phases 1–3 complete (SSL validation + basic auth).
  - Phases 4–5 (auth flow testing, LDAP-specific) planned.

- **Secret backend abstraction** (`scripts/lib/secret_backend.sh`)
  - `SECRET_BACKEND` env var selects implementation.
  - Vault backend: complete.
  - Azure backend: partial (plugin exists, not fully wired).
  - AWS/GCP: planned.

## Open Blockers / Active Decisions

### BLOCKER: Cert Rotation Never Validated
- **Risk**: Cert rotation code exists but is untested. If broken, Jenkins TLS certs
  expire silently after 30 days.
- **Required action**: Run cert rotation test plan on Ubuntu/k3s with short TTLs.
  See `docs/tests/certificate-rotation-validation.md`.
- **Test config**:
  ```bash
  export VAULT_PKI_ROLE_TTL="10m"
  export JENKINS_CERT_ROTATOR_RENEW_BEFORE="300"
  export JENKINS_CERT_ROTATOR_SCHEDULE="*/2 * * * *"
  export JENKINS_CERT_ROTATOR_ENABLED="1"
  ```
- **Manual trigger**: `kubectl create job manual-rotation --from=cronjob/jenkins-cert-rotator -n jenkins`

### PENDING: E2E AD Integration Test
- `--enable-ad` (OpenLDAP+AD-schema) path not yet validated end-to-end.
- `--enable-ad-prod` requires external AD — validate when AD environment is available.
- Test users documented in `docs/tests/active-directory-testing-instructions.md`.

### OPEN ISSUE: Basic LDAP Deploys Empty Directory
- `deploy_ldap` (standard schema) creates an empty directory with no users.
- `bootstrap-basic-schema.ldif` is planned but not yet created.
- Planned test users: `chengkai.liang`, `jenkins-admin`, `test-user` (all password: `test1234`).
- `--keep-test-users` flag planned for future.
- **Workaround**: Use `deploy_ad` (AD schema) which comes pre-seeded with test users.

### KNOWN BROKEN: `deploy_jenkins` Without `--enable-vault`
- Vault policy creation always runs during Jenkins deploy; `jenkins-admin` Vault secret
  is expected but absent when Vault is not deployed.
- Also: `deploy_jenkins --enable-ldap` without `--enable-vault` is broken for the same
  reason (LDAP credentials are pulled from Vault).

### PENDING: Documentation
- `docs/guides/certificate-rotation.md` — not yet created.
- `docs/guides/mac-ad-setup.md` — not yet created.
- `docs/guides/ad-connectivity-troubleshooting.md` — not yet created.

## Merge Criteria for `ldap-develop` → `main`

1. Cert rotation validation passes on Ubuntu/k3s (Priority 1).
2. End-to-end AD test passes with at least `--enable-ad` mode (Priority 1).
3. All existing Bats tests continue to pass (currently 36/36 on AD provider).
4. No regressions on `deploy_jenkins --enable-vault` baseline path.

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before attempting other
  service deployments. Vault seals on pod/node restart.
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`). See
  `docs/issues/2025-10-19-eso-secretstore-not-ready.md`.
- **LDAP bind DN mismatch**: Keep `LDAP_BASE_DN` in sync with base DN used in LDIF
  bootstrap files. See `docs/issues/2025-10-20-ldap-bind-dn-mismatch.md`.
