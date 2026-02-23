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

---

## Stage 1 — Lightweight Gate (no cluster required)

**Triggers:** every push to any branch

**Jobs:**
1. `shellcheck` — lint all `.sh` files under `scripts/`
2. `bash -n` — syntax validation on all scripts
3. **Lib unit BATS** — run `scripts/tests/lib/` suite:
   - `run_command.bats`
   - `sha256_12.bats`
   - `read_lines.bats`
   - `ensure_bats.bats`
   - `install_kubernetes_cli.bats`
   - `cleanup_on_success.bats`
   - `test_auth_cleanup.bats`

**Requirements:** bash, bats, shellcheck — no cluster, no Docker, no k3d

**Path filter:** skip when only `docs/`, `memory-bank/`, `*.md` change

---

## Stage 2 — Integration Gate (pre-built cluster)

**Triggers:** pull request to `main`

**Runner:** self-hosted Mac (ARM64) with persistent k3d cluster

**Pre-conditions:** cluster already running with Vault, Istio, ESO deployed

**Jobs (run in sequence, fail-fast):**
1. `test_vault` — Vault HA, Kubernetes auth, secret read verification
2. `test_eso` — ESO ClusterSecretStore + ExternalSecret sync verification
3. `test_istio` — sidecar injection, Gateway, VirtualService routing

**Cleanup:** each `test_` function has `trap ... EXIT TERM` cleanup — relies on existing
cleanup traps in `scripts/lib/test.sh`. No shared state left behind between runs.

**Parallel safety:** `test_jenkins` uses `JENKINS_NS_GENERATED` for namespace isolation —
other tests do not have this yet. Run Stage 2 jobs sequentially to avoid state collision
until namespace isolation is confirmed for all tests.

**Not included in Stage 2 (too destructive for shared cluster):**
- `test_jenkins` — deploys/tears down Jenkins; use `workflow_dispatch`
- `test_cert_rotation` — mutates TLS secret; use `workflow_dispatch`

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

The Mac runner maintains a persistent k3d cluster. Cluster is rebuilt manually when:
- k3d or Helm chart versions are bumped
- Major architecture changes affect core components
- Cluster state becomes unreliable

**Minimum cluster state for Stage 2:**
```bash
./scripts/k3d-manager create_cluster
./scripts/k3d-manager deploy_vault ha
./scripts/k3d-manager deploy_eso
./scripts/k3d-manager deploy_istio
```

Vault must be unsealed before any test run (`reunseal_vault`).

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

1. [ ] Decide on self-hosted runner — install GitHub Actions runner on Mac
2. [ ] Create `.github/actions/setup/action.yml` — install bats, shellcheck
3. [ ] Create `.github/workflows/ci.yml` — Stage 1 jobs
4. [ ] Verify Stage 1 passes on current codebase
5. [ ] Update branch protection to require Stage 1 check
6. [ ] Pre-build cluster on Mac runner
7. [ ] Add Stage 2 jobs to `ci.yml` — PR-only, integration tests
8. [ ] Add Stage 3 `workflow_dispatch` workflow
9. [ ] Update branch protection to require Stage 2 check

---

## Reference

- Provision-tomcat CI as model: `.github/workflows/ci.yml`, `bin/enforce-branch-protection`
- Test functions: `scripts/lib/test.sh`
- Unit BATS: `scripts/tests/lib/`
- Branch protection script: `provision-tomcat/bin/enforce-branch-protection`
