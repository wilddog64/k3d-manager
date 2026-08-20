# Chore: lib-acg — CI does not shellcheck bin/ scripts

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `.github/workflows/ci.yml` — add shellcheck step for `bin/` scripts

---

## Before You Start

```
git -C ~/src/gitrepo/personal/lib-acg fetch origin
git -C ~/src/gitrepo/personal/lib-acg checkout fix/acg-credentials-extend-dialog
git -C ~/src/gitrepo/personal/lib-acg pull origin fix/acg-credentials-extend-dialog
```

Read this spec in full before touching any file.

---

## Problem

The existing `lint` job shellchecks `scripts/**/*.sh` files only. `bin/acg-credential-test`
and `bin/acg-extend-test` are bash scripts with no `.sh` extension — the `find` command
misses them. Shell errors in `bin/` scripts are never caught by CI.

**Root cause:** The shellcheck step uses `find scripts -name '*.sh'`; `bin/` is not
searched and the scripts have no `.sh` extension.

---

## Fix

### Change 1 — `.github/workflows/ci.yml`: add `bin/` shellcheck step

Add a new step immediately after the existing `Run shellcheck` step.

**Exact old block (the step that follows — use as anchor for insertion):**

```yaml
      - name: Run node syntax checks
        shell: bash
        run: |
          set -euo pipefail
          find playwright -type f -name '*.js' -print0 |
          while IFS= read -r -d '' file; do
            node --check "$file"
          done
```

**Exact new block (insert the new step before the node step):**

```yaml
      - name: Run shellcheck on bin/ scripts
        shell: bash
        run: |
          set -euo pipefail
          shellcheck -S warning bin/acg-credential-test bin/acg-extend-test

      - name: Run node syntax checks
        shell: bash
        run: |
          set -euo pipefail
          find playwright -type f -name '*.js' -print0 |
          while IFS= read -r -d '' file; do
            node --check "$file"
          done
```

---

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Add `Run shellcheck on bin/ scripts` step |

---

## Rules

- `yamllint .github/workflows/ci.yml` — zero errors
- No other files modified

---

## Definition of Done

- [ ] New `Run shellcheck on bin/ scripts` step added to `lint` job in `ci.yml`
- [ ] Step runs `shellcheck -S warning bin/acg-credential-test bin/acg-extend-test`
- [ ] Step is inserted before the `Run node syntax checks` step
- [ ] `yamllint .github/workflows/ci.yml` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in lib-acg with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
chore(ci): add shellcheck step for bin/ scripts
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `.github/workflows/ci.yml`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT change the existing `Run shellcheck` step — only add the new `bin/` step
