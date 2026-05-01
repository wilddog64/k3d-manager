# Bug: stage2 CI always fails in PR context — no live cluster on self-hosted runner

**Date:** 2026-05-01
**Severity:** Medium — every PR against `main` that touches non-docs files has a failing CI
check; merging requires admin override every time.
**Root cause:** `stage2` runs on `[self-hosted, macOS, ARM64]` and immediately checks
cluster health (`check_cluster_health.sh`). The self-hosted runner does not have a live
OrbStack cluster running in PR context, so the Vault StatefulSet is never Ready and the
job always fails with `ERROR: StatefulSet vault pods not Ready in secrets`.

The existing `skip_cluster` gate only skips `stage2` for docs-only PRs. Any non-docs
change (Makefile, scripts, services/) triggers `stage2` and fails.

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager.
2. `git pull origin k3d-manager-v1.3.0` to get this spec.
3. Read this spec in full before touching anything.
4. Read the exact target file before editing:
   - `.github/workflows/ci.yml`
5. Branch: `k3d-manager-v1.3.0` — commit directly, no new branch.

---

## What to Change

### File: `.github/workflows/ci.yml`

Add `contains(github.event.pull_request.labels.*.name, 'ci:cluster-tests')` as an
additional AND condition on the `stage2` job's `if` block.

**Before** (lines 131–134):
```yaml
    if: >-
      ${{ github.event_name == 'pull_request' &&
          github.event.pull_request.head.repo.full_name == github.repository &&
          needs.detect.outputs.skip_cluster == 'false' }}
```

**After:**
```yaml
    if: >-
      ${{ github.event_name == 'pull_request' &&
          github.event.pull_request.head.repo.full_name == github.repository &&
          needs.detect.outputs.skip_cluster == 'false' &&
          contains(github.event.pull_request.labels.*.name, 'ci:cluster-tests') }}
```

No other lines change. Indentation is 4 spaces — preserve exactly.

---

## Why This Works

When the label `ci:cluster-tests` is absent, the `if` condition evaluates to `false` and
GitHub skips the job (status: `skipped`, not `failure`). A skipped job does not block
the PR. When the label is present, `stage2` runs exactly as before.

The label can be added to any PR where a live-cluster smoke test is desired (e.g. before
merging a major infra change). Normal code/fix PRs skip it automatically.

---

## Definition of Done

- [ ] `.github/workflows/ci.yml` `stage2` `if` block has the label condition added
- [ ] No other files modified
- [ ] `yamllint .github/workflows/ci.yml` passes with zero errors
- [ ] Commit on `k3d-manager-v1.3.0` with exact message:
  ```
  fix(ci): gate stage2 cluster tests behind ci:cluster-tests label

  stage2 always fails in PR context — no live OrbStack cluster on the
  self-hosted runner. Add label gate so stage2 only runs when explicitly
  opted in; without the label the job is skipped (not failed) and CI passes
  on lint + detect alone.
  ```
- [ ] `git push origin k3d-manager-v1.3.0` succeeds — do NOT report done until push confirmed
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `.github/workflows/ci.yml`
- Do NOT commit to `main`

---

## Rules

- One file, four-line change — if your diff touches anything else, stop and re-read the spec
- Preserve exact indentation (spaces, not tabs)
- `yamllint .github/workflows/ci.yml` must pass before committing
