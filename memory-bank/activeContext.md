# Active Context – k3d-manager

## Current Branch: `ldap-develop`

Active development branch for Active Directory integration, certificate rotation,
OrbStack provider, and Stage 2 CI. **Not yet merged to `main`.**

## Current Focus (as of 2026-02-25)

Complete Stage 2 CI workflow and prepare `ldap-develop` for merge to `main`.
- Stage 1 lint: ✅ green on PR #2
- Stage 2 job: next task for Codex (see below)
- m2-air cluster pre-build: pending — run `./bin/setup-mac-ci-runner.sh` on m2-air when ready

---

## What Has Been Built on `ldap-develop`

### Completed Features

- **Test strategy overhaul** (2026-02-20)
  - Removed mock-heavy, high-drift BATS suites (jenkins.bats, create_k3d_clusters.bats, etc.)
  - Added `test smoke` E2E subcommand. Unit BATS now covers pure logic only.

- **Active Directory provider** (`scripts/lib/dirservices/activedirectory.sh`)
  - All interface functions implemented. 36 BATS tests, 100% passing.
  - `TOKENGROUPS` strategy for nested group resolution. `AD_TEST_MODE=1` for offline testing.

- **OpenLDAP AD-schema variant** (`deploy_ad` command)
  - Pre-seeded with `alice` (admin), `bob` (developer), `charlie` (read-only). Password: `password`.
  - Used as local stand-in for real AD during integration testing.

- **Jenkins directory service integration**
  - `--enable-ad`, `--enable-ad-prod`, `--enable-ldap` flags implemented.
  - JCasC generation via `_dirservice_*_generate_jcasc` interface.

- **Certificate rotation CronJob** (`jenkins-cert-rotator`)
  - Triggers Vault PKI renewal, updates K8s secret, revokes old cert.
  - `JENKINS_CERT_ROTATOR_IMAGE` configurable. Validated with short TTL.

- **Jenkins smoke test** (`bin/smoke-test-jenkins.sh`)
  - SSL/auth smoke coverage. Routed into `test smoke` E2E flow.
  - macOS port-forward path: tunnels through `svc/istio-ingressgateway` in `istio-system`.
  - `JENKINS_SMOKE_IP_OVERRIDE` and `JENKINS_SMOKE_URL` env var overrides supported.
  - **Correct validation command:** `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault`
  - Never invoke `bin/smoke-test-jenkins.sh` directly — must run through the deployer.

- **Secret backend abstraction** (`scripts/lib/secret_backend.sh`)
  - Vault backend: complete. Azure: partial. AWS/GCP: planned.

- **OrbStack provider** (Phases 1 & 2 — 2026-02-24)
  - `CLUSTER_PROVIDER=orbstack` wraps k3d with OrbStack Docker context.
  - Auto-detects OrbStack on macOS via `orb status`; falls back to `k3d`.
  - **m4 validation:** ✅ complete — all integration issues resolved (see `docs/issues/`).
  - **m2-air validation:** pending — required before Phase 1+2 considered production-ready.
  - **Phase 3** (OrbStack native Kubernetes, no k3d): not yet started.

- **Stage 1 CI** (2026-02-23)
  - `.github/workflows/ci.yml`: shellcheck (shebang-scoped), bash -n, yamllint, 53 lib unit BATS.
  - Triggers on PR open/update/reopen to `main` (in-repo only).
  - `scripts/ci/check_cluster_health.sh`: Stage 2.0 health gate (Istio, Vault, ESO).
  - Namespace isolation in `scripts/lib/test.sh`: `test_vault`, `test_eso`, `test_istio`
    use ephemeral random namespaces and parameterized cleanup traps.

---

## Current Priorities / Active Decisions

### Priority 1: Finish Stage 2 CI (current task)
- Add `stage2` job to `.github/workflows/ci.yml` — see **Next Step for Codex** below.
- Pre-build cluster on m2-air once Stage 2 job exists: `./bin/setup-mac-ci-runner.sh`

### Priority 2: Jenkins Kubernetes agents and SMB CSI integration
- Next feature track after CI is stable.
- Plan: `docs/plans/jenkins-k8s-agents-and-smb-csi.md`

### Priority 3: AD end-to-end validation
- `--enable-ad` mode: provider-level unit coverage done; end-to-end scenario pending.
- `--enable-ad-prod`: requires external AD (VPN/corporate environment).

### PENDING: GitGuardian False Positive Fix
- Rename `LDAP_PASSWORD_ROTATOR_*` → `LDAP_ROTATOR_*` in `scripts/etc/ldap/vars.sh`
- See `docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md`

### OPEN ISSUE: Basic LDAP Deploys Empty Directory
- `deploy_ldap` (standard schema) creates an empty directory with no users.
- `bootstrap-basic-schema.ldif` not yet created.
- **Workaround**: use `deploy_ad` (pre-seeded with test users).

### KNOWN BROKEN: `deploy_jenkins` Without `--enable-vault`
- Vault policy creation always runs; `jenkins-admin` Vault secret absent without Vault.
- Same issue for `deploy_jenkins --enable-ldap` without `--enable-vault`.

### OPEN INVESTIGATION: LDAP password/JCasC secret interpolation
- `$${...}` escaping fix not yet confirmed working.
- See `docs/issues/2025-11-21-ldap-password-envsubst-issue.md`

### PENDING: Documentation
- `docs/guides/certificate-rotation.md` — not yet created.
- `docs/guides/mac-ad-setup.md` — not yet created.
- `docs/guides/ad-connectivity-troubleshooting.md` — not yet created.

---

## Merge Criteria for `ldap-develop` → `main`

1. Stage 2 CI runs green on PR #2.
2. End-to-end AD testing passes in `--enable-ad` mode.
3. Pure-logic BATS suites stay green after each change.
4. No regressions on `deploy_jenkins --enable-vault` baseline path.
5. Open known-broken paths are either fixed or explicitly documented with guardrails.

---

## Branch Protection (as of 2026-02-24)

Enabled on `wilddog64/k3d-manager@main`:
- 1 required PR approval, stale review dismissal, enforce admins
- No force pushes, no branch deletion
- **Required status check:** `lint` job (Stage 1)
- **After Stage 2 is green:** add `stage2` as a required check (see Codex instructions below)

---

## CI Workflow Status (2026-02-25)

Plan: `docs/plans/ci-workflow.md`

**Architecture:**
- **Stage 1** — ubuntu-latest: shellcheck, bash -n, yamllint, 53 lib BATS. No cluster needed.
- **Stage 2** — m2-air (self-hosted, macOS ARM64): health check + integration tests. PR only.
- **Stage 3** — `workflow_dispatch` only: test_jenkins, test_cert_rotation. Not yet created.

**Self-hosted runner:** `m2-air` online. Custom `ARM64` label added (system label is `X64` due
to Rosetta 2 install). Workflow must use `runs-on: [self-hosted, macOS, ARM64]`.
See `docs/issues/2026-02-25-m2-air-runner-wrong-architecture-label.md`.

**Completed tasks:**
1. ✅ Stage 1 trigger: `types: [opened, synchronize, reopened]`
2. ✅ Namespace isolation: `test_vault`, `test_eso`, `test_istio` use ephemeral namespaces
3. ✅ `test_istio` `apps/v1` regression fixed
4. ✅ `scripts/ci/check_cluster_health.sh` written and syntax-verified

**Remaining:**
5. Add `stage2` job to `ci.yml` **(next — see below)**
6. Update branch protection to require `stage2`

---

## Next Step for Codex — Add Stage 2 Job to ci.yml

**All prerequisites are complete. This is the only remaining CI implementation task.**

Add this job to `.github/workflows/ci.yml`, after the closing line of the `lint` job:

```yaml
  stage2:
    needs: lint
    if: ${{ github.event_name == 'pull_request' &&
            github.event.pull_request.head.repo.full_name == github.repository }}
    runs-on: [self-hosted, macOS, ARM64]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Cluster health check
        run: bash scripts/ci/check_cluster_health.sh

      - name: Run integration tests
        env:
          CLUSTER_PROVIDER: orbstack
        run: |
          set -euo pipefail
          ./scripts/k3d-manager test_vault
          ./scripts/k3d-manager test_eso
          ./scripts/k3d-manager test_istio
```

**After adding the job:**
1. Run `yamllint .github/workflows/ci.yml` locally — must pass before committing.
2. Push to `ldap-develop`. Stage 1 lint will re-run on PR #2.
3. Monitor `gh run list` — Stage 2 will queue on m2-air after Stage 1 passes.
4. If Stage 2 goes green, report back — Claude will update branch protection.
5. Update `memory-bank/activeContext.md` — mark step 5 ✅ in the Completed tasks list.

**Design constraints — do not violate:**
- `stage2` must declare `needs: lint` — never runs without Stage 1 passing first.
- `runs-on: [self-hosted, macOS, ARM64]` — never `ubuntu-latest`.
- `test_jenkins` and `test_cert_rotation` are NOT in Stage 2 — too destructive. Stage 3 only.
- Do not create a `workflow_dispatch` Stage 3 workflow until Stage 2 is stable.

**Step 6 — after Stage 2 goes green** (Claude will handle, not Codex):
```bash
GITHUB_REPO=k3d-manager GITHUB_OWNER=wilddog64 \
REQUIRED_STATUS_CHECK=stage2 \
/path/to/provision-tomcat/bin/enforce-branch-protection
```

Full design: `docs/plans/ci-workflow.md`
m2-air cluster setup: `./bin/setup-mac-ci-runner.sh` (handles OrbStack, cluster create, Istio/Vault/ESO, health check)
m2-air validation sequence: `docs/plans/m2-air-stage2-validation.md`

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before other deployments.
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`).
  See `docs/issues/2025-10-19-eso-secretstore-not-ready.md`.
- **LDAP bind DN mismatch**: keep `LDAP_BASE_DN` in sync with LDIF bootstrap base DN.
  See `docs/issues/2025-10-20-ldap-bind-dn-mismatch.md`.
- **Jenkins readiness timeout**: `_wait_for_jenkins_ready` uses longer timeout + pod-existence
  precheck. See `docs/issues/2025-11-07-jenkins-pod-readiness-timeout.md`.
- **GitGuardian false positive**: `LDAP_PASSWORD_ROTATOR_IMAGE` in `scripts/etc/ldap/vars.sh`
  triggered detector — variable name has "PASSWORD", value is a Docker image. No real secret.
  Pending rename to `LDAP_ROTATOR_IMAGE`. See `docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md`.
