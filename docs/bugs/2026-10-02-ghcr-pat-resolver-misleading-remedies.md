# Bug: GHCR PAT resolver reports the wrong cause and the wrong remedy

**Status:** FIXED (pending)
**Branch:** `k3d-manager-v1.40.0`
**File:** `scripts/plugins/shopping_cart.sh`
**Tests:** `scripts/tests/plugins/shopping_cart.bats`

## Symptom

`make e2e` on 2026-10-02 (runs `1790958044-29337`, `1790958376-31051`) stopped at the GHCR
pull-credential step and sent the operator in the wrong direction three times:

1. `gh CLI token cannot pull from ghcr.io — its OAuth scopes are fixed and exclude read:packages`
   — false. `gh auth refresh -h github.com -s read:packages` adds the scope to the existing
   `gh` login; after running it the next `make e2e` resolved the credential with no prompt.
2. The interactive prompt rejected a pasted keychain token with
   `the pasted PAT cannot pull from ghcr.io — it is missing the read:packages scope`. The token
   was actually **dead**: `api.github.com/user` returned **HTTP 401**. The prompt path never
   checks `/user`, so every failure is reported as a scope problem.
3. The final `_err` offers only `pbpaste | bin/rotate-ghcr-pat`, which implies minting a new PAT
   — the cheapest fix (`gh auth refresh`) is never mentioned.

## Fix

### 1 — `shopping_cart_load_ghcr_pat_from_vault`: name the cheap remedy

Old:
```bash
    _info "[acg-up] Vault PAT authenticates but cannot pull from ghcr.io — it is missing the read:packages scope; mint a PAT with read:packages and overwrite secret/github/pat"
```
New:
```bash
    _info "[acg-up] Vault PAT authenticates but cannot pull from ghcr.io — it is missing the read:packages scope; trying the gh CLI token next"
```

### 2 — `shopping_cart_load_ghcr_pat_from_gh`: correct the claim, give the command

Old:
```bash
    _info "[acg-up] gh CLI token cannot pull from ghcr.io — its OAuth scopes are fixed and exclude read:packages, so it is NOT being saved to Vault"
```
New:
```bash
    _info "[acg-up] gh CLI token cannot pull from ghcr.io (missing read:packages) — NOT saving it to Vault; add the scope with: gh auth refresh -h github.com -s read:packages"
```

### 3 — `shopping_cart_prompt_ghcr_pat`: tell a dead token from a missing scope

Old:
```bash
  if ! _shopping_cart_ghcr_pat_can_pull "${_github_user}" "${_ghcr_pat}"; then
    _warn "[acg-up] the pasted PAT cannot pull from ghcr.io — it is missing the read:packages scope; not saving it to Vault"
    _ghcr_pat=""
    return 1
  fi
```
New:
```bash
  if ! _shopping_cart_ghcr_pat_can_pull "${_github_user}" "${_ghcr_pat}"; then
    local _netrc _pat_http
    _netrc=$(mktemp) && chmod 0600 "${_netrc}"
    printf 'machine api.github.com login %s password %s\n' "${_github_user}" "${_ghcr_pat}" > "${_netrc}"
    _pat_http=$(curl -s -o /dev/null -w "%{http_code}" --netrc-file "${_netrc}" "https://api.github.com/user" 2>/dev/null || true)
    rm -f "${_netrc}"
    if [[ "${_pat_http}" != "200" ]]; then
      _warn "[acg-up] the pasted token is rejected by GitHub (HTTP ${_pat_http}) — it is expired, revoked, or not a token; not saving it to Vault"
    else
      _warn "[acg-up] the pasted token is valid but cannot pull from ghcr.io — it is missing the read:packages scope (fine-grained PATs are not accepted by GHCR); not saving it to Vault"
    fi
    _ghcr_pat=""
    return 1
  fi
```

### 4 — `shopping_cart_resolve_ghcr_pat`: lead with the cheapest remedy

Old:
```bash
  _err "[acg-up] GHCR_PAT not set and no valid PAT in Vault — set GHCR_PAT env var or run: pbpaste | bin/rotate-ghcr-pat"
```
New:
```bash
  _err "[acg-up] no credential that can pull from ghcr.io (env GHCR_PAT, Vault, gh CLI all failed) — run: gh auth refresh -h github.com -s read:packages  (or: pbpaste | bin/rotate-ghcr-pat with a classic PAT that has read:packages)"
```

## Tests (append to `scripts/tests/plugins/shopping_cart.bats`)

Follow the existing `run bash -c '…'` style used by `gh CLI PAT is not stored when the pull probe fails`.

1. **`gh CLI pull failure names gh auth refresh`** — stub `gh` (auth → token, api → 0),
   `_shopping_cart_ghcr_pat_can_pull` → 1; call `shopping_cart_load_ghcr_pat_from_gh || true`;
   assert output contains `gh auth refresh -h github.com -s read:packages` and does **not**
   contain `fixed`.
2. **`prompt reports HTTP 401 for a dead pasted token`** — the prompt bails without a TTY, so
   after sourcing the plugin, neutralise only the TTY guard for the test:
   `eval "$(declare -f shopping_cart_prompt_ghcr_pat | sed 's/\[\[ ! -t 0 || ! -t 1 \]\]/false/')"`.
   Stub `read() { _ghcr_pat="dead"; }`, `_shopping_cart_ghcr_pat_can_pull` → 1, `curl` → prints
   `401`, `_shopping_cart_store_ghcr_pat_in_vault` → appends to a marker file. Assert: the call
   returns non-zero, output contains `HTTP 401`, output does **not** contain
   `missing the read:packages`, and the marker file is empty.
3. **`prompt reports missing scope for a valid pasted token`** — same harness, `curl` prints
   `200`. Assert output contains `missing the read:packages scope` and not `HTTP`.
4. **`resolve error names gh auth refresh`** — stub the four loaders to return 1 and `_err` to
   print its argument; assert output contains `gh auth refresh -h github.com -s read:packages`.

**Mutation check (must report):** revert fix 3 only (restore the old single `_warn`) → test 2
must go red. Revert fix 2 only → test 1 must go red. Restore, all green.

## Rules

- `shellcheck scripts/plugins/shopping_cart.sh` — zero new warnings.
- `bats scripts/tests/plugins/shopping_cart.bats` — all green; paste the summary line.
- The token must never appear in argv: the new `/user` probe uses `--netrc-file`, same as the
  env and Vault paths. Do not add `-H "Authorization: token …"`.

## Definition of Done

- [ ] Fixes 1–4 applied exactly as written
- [ ] Tests 1–4 added and green; mutation results reported
- [ ] Commit message: `fix(shopping-cart): GHCR resolver names the real cause and gh auth refresh`
- [ ] Pushed to `origin/k3d-manager-v1.40.0`; report the SHA from `git rev-parse origin/k3d-manager-v1.40.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the two listed above (plus this doc's Status line)
- Do NOT commit to `main`
- Do NOT change the resolution order or add a keychain lookup
