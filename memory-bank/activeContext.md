# Active Context – k3d-manager

## Current Branch: `ldap-develop`

Active development branch for Active Directory integration, certificate rotation,
OrbStack provider, and Stage 2 CI. **Not yet merged to `main`.**

## Current Focus (as of 2026-02-26)

Complete Stage 2 CI workflow and prepare `ldap-develop` for merge to `main`.
- Stage 1 lint: ✅ green on PR #2
- m2-air cluster: ✅ OrbStack installed, `test_istio` passing
- **Blocker:** Stage 2 still pending Gemini validation; `test_vault` ✅ and `test_eso` now green locally, but m2-air rerun + branch protection update outstanding (Steps 8–9).
- Stage 2 job: ✅ merged; awaiting green run before enabling required check

### Session Notes (2026-02-27)
- Codex re-synced docs + memory-bank; applied the remaining `test_eso` fixes (apiVersion, HTTP server, jsonpath quoting) and revalidated locally with `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_eso` ✅.
- Codex fixed `test_istio` namespace references so the randomized `$test_ns` is used everywhere and validated locally via `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_istio` ✅.
- Gemini validated Jenkins smoke test fixes (VirtualService hostname detection, standalone script path normalization) — confirmed FIXED as documented. However, Gemini still has not run `test_vault`, `test_eso`, `test_istio` on m2-air after the latest fixes; Step 8 remains pending.

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
  - `_jenkins_run_smoke_test` namespace query fixed: custom hostnames now auto-detected ✅.
  - `bin/smoke-test-jenkins.sh` path normalization: standalone invocation supported ✅.
  - **Validation command:** `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault`
  - Standalone testing: `bash -x ./bin/smoke-test-jenkins.sh <args>` supported.

- **Secret backend abstraction** (`scripts/lib/secret_backend.sh`)
  - Vault backend: complete. Azure: partial. AWS/GCP: planned.

- **OrbStack provider** (Phases 1 & 2 — 2026-02-24)
  - `CLUSTER_PROVIDER=orbstack` wraps k3d with OrbStack Docker context.
  - Auto-detects OrbStack on macOS via `orb status`; falls back to `k3d`.
  - **m4 validation:** ✅ complete — all integration issues resolved (see `docs/issues/`).
  - **m2-air validation:** ⚠️ still pending — Gemini reviewed docs but did not run test_vault/test_eso/test_istio on m2-air as required.
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
5. ✅ m2-air: OrbStack installed, cluster up, `test_istio` passing (2026-02-26)
6. ✅ `test_vault` refactored to reuse existing Vault deployment (2026-02-26)
7. ✅ Stage 2 job added to `.github/workflows/ci.yml` (2026-02-26)

**Remaining:**
8. Gemini: re-run `test_eso`, `test_istio`, `test_vault` on m2-air (Stage 2 Step 8) now that all fixes are merged; capture outputs per instructions, then update this file.
9. Claude: update branch protection to require `stage2` (after step 8 green)

---

## Update — `test_eso` fix (2026-02-27)

- Status: ✅ Passed. `scripts/lib/test.sh` updated to use `v1` API, HTTP for Vault, and double quotes for `jsonpath` expansion. All E2E steps for ESO verification are now green on m2-air.

---

## Update — `test_istio` hardcoded namespace (2026-02-27)

- Status: ✅ Fixed. `scripts/lib/test.sh:test_istio` now uses the generated `$test_ns` for all
  resources (sidecar check, gateway/virtualservice applies, and lookups). Validated locally via
  `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_istio`.
- Docs: `docs/issues/2026-02-27-test-istio-hardcoded-namespace.md` updated with the fix details.
- Action: Gemini must rerun `./scripts/k3d-manager test_istio` on m2-air during Stage 2 Step 8.

---

## Update — `test_vault` refactor (2026-02-26)

- Status: ✅ Completed. `scripts/lib/test.sh:test_vault` now reuses the standing `vault`
  namespace/release, validates the namespace, StatefulSet, pod, and `vault-root` secret exist
  before running, seeds a random `secret/<path>` entry, and cleans up only the test namespace,
  temporary Vault role, and seeded secret.
- No Helm install or ClusterRoleBinding deletion occurs anymore, eliminating the
  `vault-server-binding` ownership conflict.
- Validation: `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_vault` now succeeds on the
  local cluster; mac hosts must prefer Homebrew bash (>=5) so associative arrays load properly.
- Action: Gemini still needs to rerun `./scripts/k3d-manager test_vault` on the m2-air cluster to
  confirm the fix on the shared environment before Stage 2 is enforced.

---

## Update — `test_eso` fixes (2026-02-27)

- Status: ✅ Completed and validated on m2-air by Gemini (2026-02-27). `scripts/lib/test.sh:test_eso`
  now targets the `external-secrets.io/v1` CRDs, points at Vault's internal HTTP endpoint (no TLS
  block needed), and uses double-quoted `jsonpath` expressions so `${secret_key}` expands before
  invoking `kubectl`.

---

## Next Step for Codex — Fix `test_istio` hardcoded namespace

**File:** `scripts/lib/test.sh`

**Problem:** The `test_istio` function generates a random namespace via `_test_lib_random_name 'istio-test'` and stores it in `$test_ns`, but several lines inside the function still reference the literal string `istio-test`:

| Line | Hardcoded reference |
|---|---|
| 188 | `_kubectl --no-exit get pod -n istio-test -o yaml` |
| 207 | `_kubectl apply -f - -n istio-test` |
| 212 | `namespace: istio-test` (inside heredoc) |
| 228 | `namespace: istio-test` (inside heredoc) |
| 243 | `_kubectl --no-exit get gateway -n istio-test test-gateway` |

**Also check line 275:** a second function (cleanup or teardown) has `local test_ns="${1:-istio-test}"` — confirm whether this default needs to be updated or if the caller always passes `$test_ns` explicitly.

**Fix:** Replace each hardcoded `istio-test` (except the `_test_lib_random_name` prefix on line 131) with `"$test_ns"`. Heredoc namespace fields need to use the variable via the outer scope or switch to a non-heredoc apply.

**After fixing:** commit, push, then hand off to Gemini.

**Reference:** `docs/issues/2026-02-27-test-istio-hardcoded-namespace.md`

---

## Next Step for Gemini — Re-validate on m2-air (after Codex fix)

**IMPORTANT: This task requires running shell commands on m2-air and reporting actual output.
Do NOT read documentation, review code, or summarize fixes. Execute the commands below,
capture their exit codes and output, and report exactly what happened.**

### Step 0 — Verify prerequisites (run each command, report output)

```bash
# Are you on m2-air?
hostname

# Is the repo on ldap-develop with latest changes?
git -C ~/src/gitrepo/personal/k3d-manager branch
git -C ~/src/gitrepo/personal/k3d-manager pull

# Is OrbStack running?
orb status

# Is Vault running and unsealed?
kubectl get pods -n vault

# If vault-0 shows Running but sealed, unseal it:
CLUSTER_PROVIDER=orbstack ~/src/gitrepo/personal/k3d-manager/scripts/k3d-manager reunseal_vault
```

### Step 1 — Pull latest fixes

```bash
cd ~/src/gitrepo/personal/k3d-manager
git pull
git log --oneline -3
```

**Report the output of `git log --oneline -3`.**

### Step 2 — Run test_eso (two fixes applied, retry now)

```bash
PATH="/opt/homebrew/bin:$PATH" CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_eso
echo "test_eso exit code: $?"
```

**Report the full terminal output and exit code.**

### Step 3 — Run test_istio (REQUIRED, only if Step 2 passed)

```bash
PATH="/opt/homebrew/bin:$PATH" CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_istio
echo "test_istio exit code: $?"
```

**Report the full terminal output and exit code.**

### Step 4 — Run test_vault (re-confirm, only if Step 3 passed)

```bash
PATH="/opt/homebrew/bin:$PATH" CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_vault
echo "test_vault exit code: $?"
```

**Report the full terminal output and exit code.**

### Reporting results

**If all three pass (exit code 0):**
- Update this file: mark step 8 ✅ with date and actual output summary
- Commit and push with message: `memory-bank: step 8 complete — test_vault/eso/istio green on m2-air`
- Do NOT update branch protection — that is Claude's job (step 9)

**If any test fails:**
- Stop immediately, do not run further tests
- Document the exact error output in `docs/issues/YYYY-MM-DD-<slug>.md`
- Update this file with findings
- Commit and push the issue doc
- Do NOT mark any step as complete

---

## Update — Stage 2 job added (2026-02-26)

- Status: ✅ Completed. `.github/workflows/ci.yml` now defines the `stage2` job that depends on
  `lint`, runs only for in-repo pull requests, targets `[self-hosted, macOS, ARM64]`, checks
  cluster health, then executes `test_vault`, `test_eso`, and `test_istio` with
  `CLUSTER_PROVIDER=orbstack`. The integration step exports `PATH="/opt/homebrew/bin:$PATH"` so the
  dispatcher uses Homebrew bash. `yamllint .github/workflows/ci.yml` was run locally after editing.
- Action items:
  1. Gemini: validate the updated `test_vault` against the standing m2-air cluster, then rerun the
     Stage 2 workflow via PR #2 to ensure green. (2026-02-27: test_vault ✅, test_eso 🔴)
  2. Claude: once Stage 2 is proven green, update branch protection to require the `stage2` check
     (Step 8 in the list above).
- Reference materials remain the same: `docs/plans/ci-workflow.md`,
  `docs/plans/m2-air-stage2-validation.md`, and `./bin/setup-mac-ci-runner.sh` for runner prep.

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
