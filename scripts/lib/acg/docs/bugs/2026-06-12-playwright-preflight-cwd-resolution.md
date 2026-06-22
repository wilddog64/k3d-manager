# Bugfix: playwright preflight check fails when cwd ≠ lib-acg root

**Date:** 2026-06-12
**Branch:** `feat/v0.1.8`
**Files:** `scripts/plugins/acg.sh`, `scripts/plugins/gcp.sh`

---

## Problem

`make refresh` (and any caller invoked from the consumer repo root) fails with:

```
ERROR: [acg] playwright npm module not found — run: cd <…>/scripts/lib/acg && npm install
```

even though `playwright` **is** installed (`scripts/lib/acg/node_modules/playwright`, v1.60.0).

**Root cause:** the preflight guard runs `node -e "require('playwright')"`, and `node -e`
resolves modules from the **current working directory**, not from `_LIB_ACG_ROOT`. When the
library is consumed as a subtree and the entry script runs from the consumer's repo root
(e.g. k3d-manager `make refresh`), there is no `node_modules/playwright` at that cwd, so the
check fails — a **false negative**. The actual extraction call right below it,
`node "${_LIB_ACG_ROOT}/playwright/acg_credentials.js"`, resolves correctly because node
resolves a script's `require`s from the **script file's** directory, so it would have worked.

Verified: `require('playwright')` throws from the repo root, succeeds from
`scripts/lib/acg`, and succeeds from anywhere when `NODE_PATH=<lib-acg>/node_modules` is set.

---

## Reproduction

```bash
# from a directory that is NOT the lib-acg root:
cd /tmp
node -e "require('playwright')"        # → throws: Cannot find module 'playwright'
NODE_PATH=<lib-acg>/node_modules node -e "require('playwright')"   # → OK
```

---

## Fix

Make the preflight resolve from `_LIB_ACG_ROOT` by setting `NODE_PATH` on the check command.
Three occurrences (all in scope of `_LIB_ACG_ROOT`).

### Change 1 — `scripts/plugins/acg.sh` line 292

**Exact old block:**
```bash
  if ! node -e "require('playwright')" 2>/dev/null; then
```
**Exact new block:**
```bash
  if ! NODE_PATH="${_LIB_ACG_ROOT}/node_modules" node -e "require('playwright')" 2>/dev/null; then
```

### Change 2 — `scripts/plugins/gcp.sh` line 64

**Exact old block:**
```bash
  if ! node -e "require('playwright')" 2>/dev/null; then
```
**Exact new block:**
```bash
  if ! NODE_PATH="${_LIB_ACG_ROOT}/node_modules" node -e "require('playwright')" 2>/dev/null; then
```

### Change 3 — `scripts/plugins/gcp.sh` line 154

**Exact old block:**
```bash
  if ! command -v node >/dev/null 2>&1 || ! node -e "require('playwright')" 2>/dev/null; then
```
**Exact new block:**
```bash
  if ! command -v node >/dev/null 2>&1 || ! NODE_PATH="${_LIB_ACG_ROOT}/node_modules" node -e "require('playwright')" 2>/dev/null; then
```

> Changes 1 and 2 have byte-identical old text but live in different files — match each
> within its own file. Do NOT use a cross-file global replace.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/acg.sh` | preflight `node -e require('playwright')` → prefixed with `NODE_PATH="${_LIB_ACG_ROOT}/node_modules"` |
| `scripts/plugins/gcp.sh` | same fix at both preflight checks (lines 64, 154) |

---

## Rules

- `shellcheck -S warning scripts/plugins/acg.sh scripts/plugins/gcp.sh` — zero new warnings
- No file other than the two listed targets touched
- Do NOT change the error message text or any other line

---

## Definition of Done

- [ ] 3 occurrences prefixed with `NODE_PATH="${_LIB_ACG_ROOT}/node_modules"`
- [ ] `shellcheck -S warning scripts/plugins/acg.sh scripts/plugins/gcp.sh` passes
- [ ] Functional check from a non-root cwd:
      `( cd /tmp && NODE_PATH="$(git -C <lib-acg> rev-parse --show-toplevel)/node_modules" node -e "require('playwright')" )`
      exits 0 (and confirm the bare form without NODE_PATH still throws from /tmp)
- [ ] `git grep -n "node -e \"require('playwright')\"" scripts/plugins/` shows all 3 now NODE_PATH-prefixed
- [ ] Committed and pushed to `feat/v0.1.8`
- [ ] memory-bank updated with commit SHA and task status

**After verify (operator step — note in completion report):** subtree-pull into the consumer
repo (k3d-manager): `git subtree pull --prefix scripts/lib/acg <lib-acg-remote> feat/v0.1.8 --squash`
(or the repo's standard subtree-sync command). The consumer's `NODE_PATH=… make refresh`
workaround can then be dropped.

**Commit message (exact):**
```
fix(acg,gcp): resolve playwright preflight from _LIB_ACG_ROOT (cwd-independent)
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `feat/v0.1.8`
