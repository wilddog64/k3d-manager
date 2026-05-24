# Bug: acg-up prompts for GHCR PAT mid-run when Vault token is expired

**Date:** 2026-05-24
**File:** `bin/acg-up`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

Step 5 resolves the GHCR PAT in this order:
1. `GHCR_PAT` env var (validated via GitHub API)
2. Vault `secret/data/github/pat` (validated via GitHub API)
3. Interactive `read -r -s -p` prompt — fires mid-run when Vault token is expired

The interactive prompt at step 3 blocks an otherwise unattended `make up` run. It fires
after 4 steps of cluster work have completed, requiring the user to stay at the terminal.

---

## Root Cause

There is no pre-check for `gh auth token` before falling back to the interactive prompt.
The `gh` CLI is always authenticated and its token now carries `read:packages` scope — it
is a reliable zero-expiry source that is never checked.

---

## Fix

### Change 1 — `bin/acg-up`: try `gh auth token` before the interactive prompt

Insert a `gh auth token` attempt as a third fallback (after Vault, before interactive
prompt). If `gh` is authenticated and the token validates 200 against the GitHub API, use
it and skip the prompt entirely. Also save the validated token back to Vault so subsequent
runs that reach step 5 use the Vault path.

**Exact old block (lines 404–417 — the "if [[ -z "$_ghcr_pat" ]]" inner block):**

```bash
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

**Exact new block:**

```bash
  if [[ -z "$_ghcr_pat" ]]; then
    if command -v gh >/dev/null 2>&1; then
      _gh_token=$(gh auth token 2>/dev/null || true)
      if [[ -n "$_gh_token" ]]; then
        _gh_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${_github_user}:${_gh_token}" "https://api.github.com/user" 2>/dev/null || true)
        if [[ "$_gh_http" == "200" ]]; then
          _ghcr_pat="$_gh_token"
          _info "[acg-up] using gh CLI token for ghcr-pull-secret"
          if [[ -n "${_vault_root_token:-}" ]]; then
            curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" \
              -d "{\"data\": {\"token\": \"${_ghcr_pat}\"}}" \
              "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" >/dev/null || true
            _info "[acg-up] gh CLI token saved to Vault for future runs"
          fi
        fi
      fi
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

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add `gh auth token` fallback before interactive prompt in step 5 PAT resolution |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched
- The interactive prompt block must remain intact as the final fallback — do NOT remove it

---

## Definition of Done

- [ ] `gh auth token` attempt inserted between the Vault PAT block and the interactive prompt block
- [ ] On `gh` success: token used for ghcr-pull-secret and saved to Vault; info logged
- [ ] Interactive prompt block preserved unchanged as final fallback
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-up): use gh auth token as GHCR PAT fallback — eliminate mid-run interactive prompt
```

## What NOT to Do

- Do NOT remove the interactive prompt block — keep it as final fallback
- Do NOT remove the Vault PAT lookup block — keep full resolution order
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
