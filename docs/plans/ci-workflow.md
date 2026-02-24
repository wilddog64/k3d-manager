# CI Workflow Plan

**Date:** 2026-02-22
**Status:** Decided, not yet implemented
**Blocked on:** Self-hosted GitHub Actions runner setup on Mac

---

## Design Principles

- **Local-first mandate** — all changes verified locally before push. CI is a final gate, not a
  development loop. No "push to test on GitHub."
- **Single-commit delivery** — changes committed as atomic units once locally verified.
- **Staged gates** — lightweight checks run on every push; heavy integration tests run on PR only;
  destructive tests are manual-only.
- **Pre-built cluster model** — cluster is a persistent fixture on the Mac runner. CI runs test
  functions against existing infrastructure. No cluster create/destroy per CI run.
- **Strict Secret Hygiene** — CI logs must never leak secrets. All test functions must use
  redaction or avoid printing sensitive variables (e.g., from `get-ldap-password.sh`).

---

## Stage 1 — Lightweight Gate (no cluster required)

**Triggers:** every push to any branch

**Jobs:**
1. `shellcheck` — lint all `.sh` files under `scripts/`
2. `bash -n` — syntax validation on all scripts
3. `yamllint` — validate `.github/workflows/*.yml` only (NOT `*.yaml.tmpl` — templates
   contain `${VAR}` substitution syntax that is invalid YAML until processed by `envsubst`)
4. **Lib unit BATS** — run `scripts/tests/lib/` suite:
   - `run_command.bats`
   - `sha256_12.bats`
   - `read_lines.bats`
   - `ensure_bats.bats`
   - `install_kubernetes_cli.bats`
   - `cleanup_on_success.bats`
   - `test_auth_cleanup.bats`

**Note:** `helm lint` is not applicable — this project has no local Helm charts. All charts
are upstream (installed via `helm install`). Add `helm lint` only if a local chart is
introduced under a future `charts/` directory.

**Requirements:** bash, bats, shellcheck, yamllint — no cluster, no Docker, no k3d

**Path filter:** skip when only `docs/`, `memory-bank/`, `*.md` change

---

## Stage 2 — Integration Gate (pre-built cluster)

**Triggers:** pull request to `main`

**Runner:** self-hosted Mac (ARM64) with persistent k3d cluster

**Pre-conditions:** cluster already running with Vault, Istio, ESO deployed

**Jobs (run in sequence, fail-fast):**

### Stage 2.0: Cluster Health Check
Before running any tests, verify the persistent cluster is in a known-good state.
- `check_cluster_health` — verify all core pods are `Ready`, Istio ingress is reachable, and Vault is unsealed.
- Fail immediately if the runner environment is drifted or broken.

### Stage 2.1: Integration Tests
1. `test_vault` — Vault HA, Kubernetes auth, secret read verification
2. `test_eso` — ESO ClusterSecretStore + ExternalSecret sync verification
3. `test_istio` — sidecar injection, Gateway, VirtualService routing

**Cleanup:** each `test_` function has `trap ... EXIT TERM` cleanup — relies on existing
cleanup traps in `scripts/lib/test.sh`. No shared state left behind between runs.

**Namespace Isolation Strategy:**
- All integration tests MUST be refactored to use ephemeral, randomly named namespaces (similar to `test_jenkins` using `JENKINS_NS_GENERATED`).
- This prevents cross-test state collision and is a prerequisite for parallelizing Stage 2.

**Not included in Stage 2 (too destructive for shared cluster):**
- `test_jenkins` — deploys/tears down Jenkins; use `workflow_dispatch`
- `test_cert_rotation` — mutates TLS secret; use `workflow_dispatch`

---

## Stage 2.5 — AI Code Review (future, PR only)

**Triggers:** pull request to `main` — runs after Stage 1 passes

**Purpose:** Domain-specific review that `shellcheck` cannot do — enforce project
conventions and interface contracts automatically on every PR.

**Approach:** GitHub Actions step using OpenAI API (gpt-4o-mini for cost efficiency),
analyzing only changed files in the diff. The `.clinerules` file serves as the
review prompt — project conventions are already documented there.

**What to check (shell-specific, not covered by shellcheck):**
- New provider files implement all required interface functions
  (`_cluster_provider_create`, `_cluster_provider_destroy`, `_cluster_provider_get_kubeconfig`, etc.)
- New plugins do not execute anything at source time (no side effects on `source`)
- New sensitive flags are added to `_args_have_sensitive_flag` in `scripts/lib/system.sh`
- Public functions use no leading underscore; private functions always use `_` prefix
- `_run_command` is used instead of calling `kubectl`, `helm`, `sudo` directly

**Cost controls (same as standard practice):**
- Skip files >50KB
- Analyze diff only, not full file content
- Batch with rate-limiting delays
- Only trigger on `.sh` file changes

**Not a replacement for:**
- `shellcheck` — still runs in Stage 1 for syntax and style
- Human review — AI review is advisory, not a merge gate (at least initially)

**Implementation:** Not yet designed. Reference:
[AI-Powered Code Review with GitHub Actions](https://dev.to/paul_robertson_e844997d2b/ai-powered-code-review-automate-pull-request-analysis-with-github-actions-j90)

---

## Stage 3 — Destructive / Heavy Tests (manual trigger only)

**Triggers:** `workflow_dispatch` only — never automatic

**Jobs:**
- `test_jenkins` — full Jenkins deploy, Vault policies, TLS, authentication
- `test_jenkins_smoke` — lighter Jenkins ingress/auth check
- `test_cert_rotation` — certificate rotation with serial comparison (fast/manual/auto modes)
- `test_nfs_direct` / `test_nfs_connectivity` — NFS mount validation (environment-specific)

**When to run:**
- Before merging a Jenkins-related feature
- After cert rotation logic changes
- On-demand cluster health verification

---

## Pre-Built Cluster Setup

The Mac runner (`m2-air`) maintains a persistent k3d cluster backed by OrbStack.
Cluster is rebuilt manually when:
- k3d or Helm chart versions are bumped
- Major architecture changes affect core components
- Cluster state becomes unreliable

### Runner Prerequisites (one-time manual setup)

OrbStack must be pre-installed and configured on `m2-air` before any Stage 2 CI job
runs. CI has no human interaction — OrbStack cannot be installed or set up by CI.

```bash
# On m2-air — do this once, manually
brew install orbstack
# Open OrbStack.app and complete GUI onboarding
orb status   # must return healthy before proceeding
```

All other tooling (`kubectl`, `helm`, `k3d`, `bats`, `shellcheck`) is installed by
the Stage 1 setup action and does not require manual pre-installation.

### Minimum Cluster State for Stage 2

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager create_cluster
./scripts/k3d-manager deploy_vault ha
./scripts/k3d-manager deploy_eso
./scripts/k3d-manager deploy_istio
./scripts/k3d-manager reunseal_vault
```

Vault must be unsealed before any test run (`reunseal_vault`).

**Note:** OrbStack is a CI runner prerequisite, not a developer prerequisite. Local
dev machines can use Docker Desktop, Colima, or OrbStack — `CLUSTER_PROVIDER` selects
the right runtime. `_install_orbstack` (macOS-only) installs via Homebrew, launches
OrbStack.app, and waits for `orb status` to succeed, but CI still requires OrbStack
to be pre-installed manually.

---

## Branch Protection Update

Once Stage 1 CI is wired, update branch protection to require the lint/unit job:

```bash
GITHUB_REPO=k3d-manager \
GITHUB_OWNER=wilddog64 \
REQUIRED_STATUS_CHECK=lint \
/path/to/provision-tomcat/bin/enforce-branch-protection
```

Once Stage 2 is stable, add integration job as a required check as well.

---

## Implementation Sequence

1. [x] Decide on self-hosted runner — install GitHub Actions runner on Mac (runner: m2-air, online)
2. [x] Create `.github/actions/setup/action.yml` — install bats, shellcheck, yamllint
3. [x] Create `.github/workflows/ci.yml` — Stage 1 jobs (shellcheck + bash-n + yamllint on workflows + unit BATS)
4. [ ] **Refactor `test.sh` for namespace isolation across all integration tests**
5. [x] Verify Stage 1 passes on current codebase
6. [x] Update branch protection to require Stage 1 check
7. [ ] Pre-build cluster on Mac runner
8. [ ] Create `check_cluster_health.sh` script for Stage 2.0
9. [ ] Add Stage 2 jobs to `ci.yml` — PR-only, integration tests
10. [ ] Add Stage 3 `workflow_dispatch` workflow
11. [ ] Update branch protection to require Stage 2 check

---

## Reference

- Provision-tomcat CI as model: `.github/workflows/ci.yml`, `bin/enforce-branch-protection`
- Test functions: `scripts/lib/test.sh`
- Unit BATS: `scripts/tests/lib/`
- Branch protection script: `provision-tomcat/bin/enforce-branch-protection`
