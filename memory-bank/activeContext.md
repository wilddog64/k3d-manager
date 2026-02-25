# Active Context – k3d-manager

## Current Branch: `ldap-develop`

This is the active development branch for Active Directory integration and certificate
rotation. It has NOT been merged to `main` yet.

## Session Objective (as of 2026-02-20)

- Keep memory bank aligned with `CLAUDE.md`, `docs/issues/`, and current code behavior.
- Capture the test strategy overhaul and current post-overhaul priorities.

## What Has Been Built on `ldap-develop`

### Completed Features
- **Test strategy overhaul** (2026-02-20)
  - Removed mock-heavy, high-drift BATS suites:
    - `scripts/tests/plugins/jenkins.bats`
    - `scripts/tests/core/create_k3d_clusters.bats`
    - `scripts/tests/core/deploy_cluster.bats`
    - `scripts/tests/core/install_k3d.bats`
  - Added `test smoke` E2E subcommand in `scripts/lib/help/utils.sh`.
  - Current unit-test set is focused on pure logic and deterministic behavior.

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
  - Triggers Vault PKI renewal, updates K8s secret, revokes old cert.
  - CronJob image configurable via `JENKINS_CERT_ROTATOR_IMAGE`.
  - Rotation auth/template issue fixed (`envsubst` default-value pitfall).
  - Certificate rotation validated with short TTL and manual job runs.

- **Jenkins smoke test** (`bin/smoke-test-jenkins.sh`)
  - SSL/auth smoke coverage exists.
  - Routed into `test smoke` flow as part of E2E strategy.

- **Secret backend abstraction** (`scripts/lib/secret_backend.sh`)
  - `SECRET_BACKEND` env var selects implementation.
  - Vault backend: complete.
  - Azure backend: partial (plugin exists, not fully wired).
  - AWS/GCP: planned.

- **OrbStack provider support** (Phases 1 & 2 complete — 2026-02-24)
  - `CLUSTER_PROVIDER=orbstack` delegates all k3d operations to OrbStack's Docker runtime.
  - Auto-detects OrbStack on macOS via `orb status`; falls back to `k3d` when not running.
  - No Docker Desktop/Colima installation attempts when using OrbStack.

## Current Priorities / Active Decisions

### Priority 1: Jenkins Kubernetes agents and SMB CSI integration
- Next feature track after test overhaul completion.
- Plan: `docs/plans/jenkins-k8s-agents-and-smb-csi.md`.

### Priority 2: Expand and operationalize E2E smoke coverage
- Validate deployment flag combinations in live-cluster workflow.
- Continue to treat pure-logic BATS as fast regression checks.

### Priority 3: AD end-to-end validation depth
- `--enable-ad` path has provider-level/unit coverage; continue end-to-end scenario validation.
- `--enable-ad-prod` requires external AD (VPN/corporate environment dependent).

### Priority 4: OrbStack provider (updated 2026-02-24)
- Plan: `docs/plans/orbstack-provider.md`
- **Phase 1 + 2 implemented** — new `orbstack` provider wraps k3d with OrbStack context handling and macOS auto-detection chooses it when `orb` is running. Manual override: `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager create_cluster`.
- **Phase 3 (next)**: OrbStack native Kubernetes provider — eliminates k3d entirely (estimated half day, still pending).
- **COMPLETE: m4 local validation** — Phase 1+2 provider verified on M4 Mac (2026-02-24).
  - `_install_orbstack` successfully installed and initialized OrbStack via Homebrew.
  - Auto-detection correctly selects `orbstack` provider when running.
  - `create_cluster --dry-run` and `deploy_cluster` fixes verified (grep and guard clause issues resolved).
  - Docker context confirmed as `orbstack`.
  - **Full-Stack Integration Results:**
    - `deploy_istio` (via `deploy_cluster`) successful; all Istio pods Running.
    - `deploy_vault` fails on macOS during `_vault_ensure_data_path` due to host-side `mkdir -p` attempt on VM-only paths (see `docs/issues/2026-02-24-macos-vault-local-path-creation-failure.md`).
    - `deploy_jenkins --enable-vault` (no directory service) fails its smoke test due to unresolved JCasC variables (see `docs/issues/2026-02-24-jenkins-none-auth-mode-smoke-test-failure.md`).
- **Immediate Fix Plan (2026-02-24):** See `docs/plans/orbstack-macos-validation-fix-plan.md`
  1. `_vault_ensure_data_path` macOS guard merged + validated via
     `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_vault ha`.
  2. Jenkins `none`-auth templating rebuilt — `scripts/plugins/jenkins.sh` now keeps a
     local security realm, injects `VAULT_PKI_LEAF_HOST` into the controller env, and
     replaces the matrix permissions list. LDAP/AD smoke tests still pending but
     baseline deploy succeeds.
  3. Smoke-test routing fix **implemented 2026-02-25**:
     - `_jenkins_run_smoke_test` now detects macOS + RFC-1918 ingress IPs, launches a
       background `kubectl port-forward -n <ns> svc/jenkins 8443:443`, and exports
       `JENKINS_SMOKE_IP_OVERRIDE=127.0.0.1` so the smoke script talks to the local port
       with the correct SNI. Exit traps ensure the port-forward PID is killed even when
       the smoke script fails or is interrupted.
     - `bin/smoke-test-jenkins.sh` respects both
       `JENKINS_SMOKE_IP_OVERRIDE` (skip ingress IP lookup / reuse provided IP) and
       `JENKINS_SMOKE_URL` (full URL override for CI or remote topologies). When no
       override is present, Linux behavior is unchanged.
     - doc reference: `docs/issues/2026-02-25-jenkins-smoke-test-ingress-retries.md`.
- **COMPLETE: m4 bug fix validation (2026-02-25)**
  - **Vault macOS fix:** ✅ Verified. `deploy_vault` succeeds without host-side `mkdir` errors.
  - **Jenkins JCasC Fix:** ✅ Verified. Jenkins logs no longer show unresolved `chart-admin-*` variables in `none` auth mode.
  - **Lib unit tests:** ✅ 53/53 pass (requires `PATH="/opt/homebrew/bin:$PATH"` on macOS for bash 5).
  - **Orphan cleanup:** ✅ Trap-based cleanup correctly kills background port-forward on failure.
  - **Smoke test routing:** ✅ Fixed. `_jenkins_run_smoke_test` now queries the Jenkins VirtualService in the active namespace instead of `istio-system`, so custom hostnames are detected correctly. See `docs/issues/2026-02-25-jenkins-smoke-test-hostname-detection-failure.md`.
  - **Smoke script standalone failure:** ✅ Fixed. `bin/smoke-test-jenkins.sh` now normalizes `SCRIPT_DIR`/`PLUGINS_DIR` to the repo's `scripts/` tree before sourcing helpers, so `_vault_exec` loads without nounset exits whether the script is invoked via the deployer or directly. See `docs/issues/2026-02-25-smoke-script-standalone-dependency-failure.md`.
  - **Correct validation command** (for Gemini and Codex):
    ```bash
    CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault
    ```
    Never invoke `bin/smoke-test-jenkins.sh` directly — it must run through the deployer.

- **PENDING: m2-air validation** — only after m4 provider passes (integration issues documented). Pre-builds the Stage 2 CI cluster fixture.
- **OrbStack installer helper** — `_install_orbstack` (macOS only) installs via `brew install orbstack`, launches OrbStack.app, and waits for `orb status` to pass so scripts can continue. Users still need to complete GUI onboarding when prompted. CI runners (`m2-air`) require OrbStack pre-installed manually — see `docs/plans/ci-workflow.md` Pre-Built Cluster Setup section.

### PENDING: GitGuardian False Positive Fix
- Rename `LDAP_PASSWORD_ROTATOR_*` → `LDAP_ROTATOR_*` in `scripts/etc/ldap/vars.sh`
- Also update any referencing scripts
- See `docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md`

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

### OPEN INVESTIGATION: LDAP password/JCasC secret interpolation
- Issue documented in `docs/issues/2025-11-21-ldap-password-envsubst-issue.md`.
- Current fix attempt (`$${...}` escaping) did not yet produce confirmed working dynamic password refresh behavior.

### PENDING: Documentation
- `docs/guides/certificate-rotation.md` — not yet created.
- `docs/guides/mac-ad-setup.md` — not yet created.
- `docs/guides/ad-connectivity-troubleshooting.md` — not yet created.

## Merge Criteria for `ldap-develop` → `main`

1. E2E smoke workflow is stable for baseline and key auth/deploy combinations.
2. End-to-end AD testing passes in at least `--enable-ad` mode.
3. Pure-logic BATS suites stay green after each change.
4. No regressions on `deploy_jenkins --enable-vault` baseline path.
5. Open known-broken paths are either fixed or explicitly documented with guardrails.

## Branch Protection — Applied 2026-02-22

Branch protection is now enabled on `wilddog64/k3d-manager@main`:
- 1 required PR approval before merge
- Dismiss stale reviews on new commits
- Enforce admins — no bypass
- No force pushes, no branch deletion
- **No required status checks yet** — CI workflow not designed

When CI is ready, update protection via provision-tomcat's `bin/enforce-branch-protection`:
```bash
GITHUB_REPO=k3d-manager GITHUB_OWNER=wilddog64 \
REQUIRED_STATUS_CHECK=<job-name> \
/path/to/provision-tomcat/bin/enforce-branch-protection
```

## CI Workflow — Stage 1 Implemented (2026-02-23)

Plan: `docs/plans/ci-workflow.md`

**Decision:** Local-first mandate remains primary discipline. CI is a final gate, not a development loop.

**Staged approach:**
- **Stage 1** — Lightweight gate (no cluster): `shellcheck`, `bash -n`, `yamllint` (workflow files only, not `.yaml.tmpl`), lib unit BATS
- **Stage 2** — Integration gate (pre-built cluster, self-hosted Mac runner):
  - **Stage 2.0:** Cluster health check (verify pods Ready, Istio, Vault unsealed)
  - **Stage 2.1:** Integration tests (`test_vault`, `test_eso`, `test_istio`) on PR only
- **Stage 3** — Destructive/heavy tests: `test_cert_rotation`, `test_jenkins` via `workflow_dispatch` only

**Pre-built cluster model:** cluster is a persistent fixture on the Mac runner. CI runs test functions against it — no cluster create/destroy per run. Heavy setup cost is paid once.

**Prerequisite:** Refactor `scripts/lib/test.sh` for namespace isolation across all integration tests to prevent state collision.

**Implemented now (Stage 1):**
- Added `.github/workflows/ci.yml` and `.github/actions/setup/action.yml`.
- Added `.shellcheckrc` baseline with `disable=SC2148`.
- Scoped shellcheck in CI to files with a Bash shebang.
- Local Stage 1 verification succeeded for:
  - shebang-scoped `shellcheck -S error`
  - `bash -n` on scripts
  - `yamllint .github/workflows/*.yml`
  - `bats scripts/tests/lib`
- **2026-02-25:** Workflow now triggers on `pull_request` (base `main`) as well as `push`,
  so Stage 1 linting always runs for PRs even when the latest commits are docs-only. See
  `docs/issues/2026-02-25-ci-workflow-pr-trigger-missing.md`.

**Self-hosted runner:** `m2-air` (macOS, ARM64) — online and registered on `wilddog64/k3d-manager`.
- **Architecture label issue:** Runner registered with system label `X64` (likely installed under Rosetta 2). Custom `ARM64` label added via API as mitigation. CI workflow files must use `runs-on: [self-hosted, macOS, ARM64]`. Permanent fix: re-register runner natively. See `docs/issues/2026-02-25-m2-air-runner-wrong-architecture-label.md`.

**Branch protection:** `main` now requires `lint` job to pass before merge (updated 2026-02-24).

**Still not done:**
- Stage 2/3 CI workflows not implemented yet
- Namespace isolation refactor in `scripts/lib/test.sh` (prerequisite for Stage 2)
- Stage 2 prep/automation tracked in `docs/plans/m2-air-stage2-validation.md` — follow
  that plan to keep the m2-air runner healthy and to script the Stage 2 job once
  namespace isolation lands.

## PR Creation Instructions for Codex

The `ldap-develop` branch is 30+ commits ahead of `origin/ldap-develop` and has not
been pushed yet. To trigger Stage 1 CI:

### Step 1 — Push the branch
```bash
git push origin ldap-develop
```

### Step 2 — Create PR via GitHub CLI
```bash
gh pr create \
  --base main \
  --head ldap-develop \
  --title "OrbStack provider Phase 1+2, Stage 1 CI, AD integration, cert rotation" \
  --body "$(cat <<'EOF'
## Summary
- OrbStack provider (Phase 1+2): CLUSTER_PROVIDER=orbstack wraps k3d with OrbStack context; auto-detection on macOS
- macOS smoke test routing: port-forward through istio-ingressgateway with RFC-1918 detection and trap cleanup
- Jenkins none-auth JCasC fix: local security realm preserved when no directory service enabled
- Vault macOS mkdir fix: skip host-side PV directory creation on macOS
- Active Directory provider: full implementation with 36 BATS tests
- Jenkins cert rotation CronJob: complete
- Stage 1 CI: shellcheck, bash -n, yamllint, lib unit BATS (green)
- Self-hosted runner m2-air registered

## What CI will run
- Stage 1 (lint job): shellcheck + bash -n + yamllint + 53 lib unit BATS — runs automatically
- Stage 2: NOT yet — m2-air cluster not pre-built yet

## Notes
- Branch protection requires `lint` job to pass before merge
- 1 PR approval required before merge
- Do NOT merge until Stage 1 is green and PR is approved
EOF
)"
```

### What to watch for
- `lint` job on GitHub Actions must go green — check at `https://github.com/wilddog64/k3d-manager/actions`
- If any shellcheck or BATS failure appears, report it — do not push fixes directly to `main`
- Stage 2 will not run yet — `m2-air` cluster pre-build is a separate step after PR is approved

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before attempting other
  service deployments. Vault seals on pod/node restart.
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`). See
  `docs/issues/2025-10-19-eso-secretstore-not-ready.md`.
- **LDAP bind DN mismatch**: Keep `LDAP_BASE_DN` in sync with base DN used in LDIF
  bootstrap files. See `docs/issues/2025-10-20-ldap-bind-dn-mismatch.md`.
- **Jenkins readiness timeout behavior**: `_wait_for_jenkins_ready` now uses a longer default timeout,
  pod-existence precheck, and richer timeout diagnostics. See
  `docs/issues/2025-11-07-jenkins-pod-readiness-timeout.md`.
- **GitGuardian false positive** (2026-02-23): `LDAP_PASSWORD_ROTATOR_IMAGE` in
  `scripts/etc/ldap/vars.sh` triggered GitGuardian's generic password detector — variable
  name contains "PASSWORD", value is a Docker image. No real secret exposed. Pending fix:
  rename to `LDAP_ROTATOR_IMAGE` (and related vars). See
  `docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md`.
