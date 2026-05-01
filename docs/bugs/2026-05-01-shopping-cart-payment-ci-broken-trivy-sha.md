# Bug: shopping-cart-payment CI broken — invalid Trivy action SHA

**Date:** 2026-05-01
**Severity:** High — `shopping-cart-payment:latest` image never pushed to GHCR; pod stuck in ImagePullBackOff
**Root cause:** `.github/workflows/ci.yaml` line 217 pins `build-push-deploy.yml` at SHA `999f8d70277b92d928412ff694852b05044dbb75` which resolves to `aquasecurity/trivy-action@0.30.0` — that version does not exist. CI fails on every `main` push in the `Build, Scan & Push` job.
**Evidence:** `gh run list --repo wilddog64/shopping-cart-payment` — last two `main` push runs both failed with `Unable to resolve action 'aquasecurity/trivy-action@0.30.0'`. Same fix was applied to `shopping-cart-order` (PR #27, commit `64f82fe3`).

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager.
2. `git pull origin k3d-manager-v1.3.0` in the k3d-manager repo to get this spec.
3. Read this spec in full before touching anything.
4. `Branch (work repo): fix/ci-trivy-sha` — create from `origin/main` in `shopping-cart-payment`.
5. Read the exact target file before editing:
   - `/Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-payment/.github/workflows/ci.yaml`

---

## What to Change

**File:** `.github/workflows/ci.yaml`
**Line:** 217

**Before:**
```yaml
    uses: wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@999f8d70277b92d928412ff694852b05044dbb75
```

**After:**
```yaml
    uses: wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@39c3072759bf7da92ec8cd08653e67d7f62d4032
```

No other changes. One line, one repo.

---

## Definition of Done

- [ ] `.github/workflows/ci.yaml` line 217 has SHA `39c3072759bf7da92ec8cd08653e67d7f62d4032`
- [ ] No other files modified
- [ ] Pre-commit hooks pass (run without `--no-verify`)
- [ ] Commit on branch `fix/ci-trivy-sha` in `shopping-cart-payment` with exact message:
  ```
  fix(ci): bump build-push-deploy SHA to resolve trivy-action@v0.35.0

  @999f8d70 pinned aquasecurity/trivy-action@0.30.0 which does not exist;
  @39c3072 pins trivy-action@v0.35.0 (same fix applied to shopping-cart-order PR #27).
  ```
- [ ] `git push origin fix/ci-trivy-sha` succeeds — do NOT report done until push is confirmed
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with the commit SHA and status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `.github/workflows/ci.yaml`
- Do NOT commit to `main` — work on `fix/ci-trivy-sha`
- Do NOT modify any k3d-manager files

---

## Rules

- One file, one line change — if your diff is larger, stop and re-read the spec
- `PRE_COMMIT_ALLOW_NO_CONFIG=1` prefix required for git commands in shopping-cart-payment (no `.pre-commit-config.yaml` in that repo)
