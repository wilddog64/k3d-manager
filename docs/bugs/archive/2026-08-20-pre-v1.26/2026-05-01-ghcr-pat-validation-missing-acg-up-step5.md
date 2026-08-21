# Bug: acg-up Step 5 applies Vault PAT without validating it

**Date:** 2026-05-01
**Severity:** High — all shopping-cart pods enter ImagePullBackOff on every cluster rebuild when Vault PAT has expired
**Root cause:** `bin/acg-up` Step 5 reads the PAT from Vault and applies it to `ghcr-pull-secret` in all namespaces without first checking if the token is still valid. `bin/rotate-ghcr-pat` has the same bug in interactive mode: it prefers the Vault PAT over user input even when the Vault PAT is expired, so the user's new PAT is never applied.

**Evidence:**
- Vault PAT `ghp_QS08...` returns HTTP 401 from `api.github.com/user` — expired
- `acg-up` Step 5 ran, found the Vault PAT, applied it — cluster secrets now have an expired token
- `rotate-ghcr-pat` run interactively: reads same expired PAT from Vault, prints "Using PAT from Vault...", applies it again — no way for user to enter a new one
- All 5 pods in `ImagePullBackOff` after rebuild

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager.
2. `git pull origin k3d-manager-v1.3.0` to get this spec.
3. Read this spec in full before touching anything.
4. Read the exact target files before editing:
   - `bin/acg-up`
   - `bin/rotate-ghcr-pat`
5. Branch (work repo): `k3d-manager-v1.3.0` — commit directly to this branch, no new branch needed.

---

## What to Change

### File 1: `bin/acg-up`

**Location:** Lines 212–217 (the `if [[ -n "$_ghcr_pat" ]]; then ... else _err ...` block inside Step 5)

**Before:**
```bash
  if [[ -n "$_ghcr_pat" ]]; then
    _info "[acg-up] using PAT from Vault for ghcr-pull-secret"
  else
    _err "[acg-up] GHCR_PAT not set and no PAT found in Vault at secret/data/github/pat — run bin/rotate-ghcr-pat with a read:packages PAT"
  fi
```

**After:**
```bash
  if [[ -n "$_ghcr_pat" ]]; then
    _pat_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${_github_user}:${_ghcr_pat}" "https://api.github.com/user" 2>/dev/null || true)
    if [[ "$_pat_http" == "200" ]]; then
      _info "[acg-up] using PAT from Vault for ghcr-pull-secret"
    else
      _info "[acg-up] Vault PAT is expired (HTTP ${_pat_http}) — prompting for a new one"
      _ghcr_pat=""
    fi
  fi
  if [[ -z "$_ghcr_pat" ]]; then
    if [[ -t 0 && -t 1 ]]; then
      read -r -s -p "[acg-up] Paste GitHub PAT (repo + read:packages) and press Enter: " _ghcr_pat
      echo ""
      if [[ -n "${_vault_root_token:-}" && -n "$_ghcr_pat" ]]; then
        curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" \
          -d "{\"data\": {\"token\": \"${_ghcr_pat}\"}}" \
          "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" >/dev/null || true
        _info "[acg-up] new PAT saved to Vault"
      fi
    else
      _err "[acg-up] GHCR_PAT not set and no valid PAT in Vault — set GHCR_PAT env var or run: pbpaste | bin/rotate-ghcr-pat"
    fi
  fi
```

---

### File 2: `bin/rotate-ghcr-pat`

**Location:** Lines 36–41 (the `if [[ -n "${TOKEN:-}" ]]; then echo "Using PAT from Vault..." else read ...` block)

**Before:**
```bash
  if [[ -n "${TOKEN:-}" ]]; then
    echo "Using PAT from Vault..."
  else
    read -r -s -p "Paste new GitHub PAT (read:packages scope) and press Enter: " TOKEN
    echo ""
  fi
```

**After:**
```bash
  if [[ -n "${TOKEN:-}" ]]; then
    _pat_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${SHOPPING_CART_ORG}:${TOKEN}" "https://api.github.com/user" 2>/dev/null || true)
    if [[ "$_pat_http" == "200" ]]; then
      echo "Using PAT from Vault..."
    else
      echo "⚠️  Vault PAT is expired (HTTP ${_pat_http}) — please paste a new one" >&2
      TOKEN=""
    fi
  fi
  if [[ -z "${TOKEN:-}" ]]; then
    read -r -s -p "Paste new GitHub PAT (repo + read:packages) and press Enter: " TOKEN
    echo ""
  fi
```

---

## Definition of Done

- [ ] `bin/acg-up`: validation + prompt block matches **After** exactly (indentation preserved)
- [ ] `bin/rotate-ghcr-pat`: validation + prompt block matches **After** exactly
- [ ] No other files modified
- [ ] `shellcheck bin/acg-up` and `shellcheck bin/rotate-ghcr-pat` pass with zero new warnings
- [ ] Commit on `k3d-manager-v1.3.0` with exact message:
  ```
  fix(acg-up): validate Vault PAT before applying to ghcr-pull-secret

  Vault PAT may be expired; acg-up Step 5 and rotate-ghcr-pat now validate
  the token against api.github.com/user (HTTP 200) before use. If expired,
  acg-up prompts interactively and persists the new PAT to Vault.
  rotate-ghcr-pat falls through to the manual prompt instead of silently
  using a dead token.
  ```
- [ ] `git push origin k3d-manager-v1.3.0` succeeds — do NOT report done until push is confirmed
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with the commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `bin/acg-up` and `bin/rotate-ghcr-pat`
- Do NOT commit to `main`
- Do NOT change the surrounding Step 5 logic — only the PAT validation/prompt block

---

## Rules

- Two files, targeted block replacements — if your diff touches anything else, stop and re-read the spec
- Preserve existing indentation exactly (2-space for `bin/acg-up`, no-indent for top-level `bin/rotate-ghcr-pat`)
- `shellcheck` must pass on both files before committing
