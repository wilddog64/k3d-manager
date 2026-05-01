# Bug: Makefile injects gh OAuth token as GHCR_PAT, bypassing Vault validation

**Date:** 2026-05-01
**Severity:** High — every `make up` overwrites `ghcr-pull-secret` with the OAuth token (`gho_`), which lacks `read:packages`; all pods enter ImagePullBackOff on every cluster rebuild
**Root cause:** `Makefile` line 7: `GHCR_PAT ?= $(shell gh auth token 2>/dev/null)` sets `GHCR_PAT` to the `gh` CLI OAuth token before `acg-up` starts. `acg-up` Step 5 sees `GHCR_PAT` already set, skips the Vault path entirely, and applies the OAuth token directly. The Vault validation added in `3a0901cc` never fires.

**This also means `acg-up` Step 5 never validates a PAT supplied via env var.** If `GHCR_PAT` is set (from Makefile or user env) to an invalid token, it is applied without any check.

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager.
2. `git pull origin k3d-manager-v1.3.0` to get this spec.
3. Read this spec in full before touching anything.
4. Read the exact target files before editing:
   - `Makefile`
   - `bin/acg-up`
5. Branch: `k3d-manager-v1.3.0` — commit directly, no new branch.

---

## What to Change

### File 1: `Makefile`

**Change 1 — remove the OAuth fallback (line 7):**

**Before:**
```makefile
GHCR_PAT ?= $(shell gh auth token 2>/dev/null)
```

**After:**
```makefile
GHCR_PAT ?=
```

This means `GHCR_PAT` is empty unless the user explicitly exports it. `acg-up` will then always go through the Vault path.

---

### File 2: `bin/acg-up`

**Change 2 — validate env-supplied PAT before using it (Step 5, around line 204):**

**Before:**
```bash
_ghcr_pat="${GHCR_PAT:-}"
_github_user="${GITHUB_USERNAME:-wilddog64}"
if [[ -z "$_ghcr_pat" ]]; then
  _info "[acg-up] GHCR_PAT not in env — checking Vault..."
```

**After:**
```bash
_ghcr_pat="${GHCR_PAT:-}"
_github_user="${GITHUB_USERNAME:-wilddog64}"
if [[ -n "$_ghcr_pat" ]]; then
  _pat_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${_github_user}:${_ghcr_pat}" "https://api.github.com/user" 2>/dev/null || true)
  if [[ "$_pat_http" != "200" ]]; then
    _info "[acg-up] GHCR_PAT env var is invalid (HTTP ${_pat_http}) — falling back to Vault"
    _ghcr_pat=""
  else
    _info "[acg-up] using validated GHCR_PAT from env for ghcr-pull-secret"
  fi
fi
if [[ -z "$_ghcr_pat" ]]; then
  _info "[acg-up] GHCR_PAT not in env — checking Vault..."
```

---

## Definition of Done

- [ ] `Makefile` line 7: `GHCR_PAT ?=` (no OAuth fallback)
- [ ] `bin/acg-up`: env-var validation block inserted before the existing Vault check block
- [ ] No other files modified
- [ ] `shellcheck bin/acg-up` passes with zero new warnings
- [ ] Commit on `k3d-manager-v1.3.0` with exact message:
  ```
  fix(makefile): remove gh OAuth token fallback for GHCR_PAT

  Makefile was setting GHCR_PAT=$(gh auth token) which bypassed the Vault
  PAT validation added in 3a0901cc — the OAuth token lacks read:packages so
  every make up overwrote ghcr-pull-secret with an unusable token.

  Also add validation in acg-up Step 5 for env-supplied PAT: if GHCR_PAT is
  set but invalid (non-200 from api.github.com), fall back to Vault instead
  of applying a bad token.
  ```
- [ ] `git push origin k3d-manager-v1.3.0` succeeds — do NOT report done until push is confirmed
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `Makefile` and `bin/acg-up`
- Do NOT commit to `main`

---

## Rules

- Two files, targeted changes — if your diff touches anything else, stop and re-read the spec
- Preserve existing Makefile formatting (tabs, not spaces)
- `shellcheck bin/acg-up` must pass before committing
