# GHCR PAT is validated for authentication but never for `read:packages`, so the system converges on a permanently broken pull credential

**Filed:** 2026-09-21
**Branch:** `k3d-manager-v1.36.0`
**Severity:** High — every private image pull on the hub 403s while ESO, ArgoCD and the PAT
validation all report green.
**Status:** Open

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
2. `git pull origin k3d-manager-v1.36.0` — work on that branch, never `main`.
3. Read these files in full before editing:
   - `scripts/plugins/shopping_cart.sh` — lines 240-357 hold all four PAT loaders
   - `scripts/tests/plugins/shopping_cart.bats` — the test conventions you must match
4. Branch (all work): `k3d-manager-v1.36.0` (this repo only — single-repo task).
5. There is **no live cluster in scope**. Do not run `kubectl` against anything, do not attempt to
   fix the credential itself, and do not touch Vault. This task is code + BATS only.

## Symptom

All four `shopping-cart-apps` deployments have been in `ImagePullBackOff` for 11h on the hub,
which is what raised the `ServiceDown` critical that paged the operator on 2026-09-21:

```
shopping-cart-apps   basket-service-7d6db9b896-vdxfp     0/1   ImagePullBackOff   11h
shopping-cart-apps   frontend-67b977d7b4-chq8r           0/1   ImagePullBackOff   11h
shopping-cart-apps   order-service-6dcf65d6b4-q2qmd      0/1   ImagePullBackOff   11h
shopping-cart-apps   product-catalog-647dbfd5df-x5qgq    0/1   ImagePullBackOff   11h
```

```
Failed to pull image "ghcr.io/wilddog64/shopping-cart-basket:sha-0d8ab3ba…":
  unexpected status from HEAD request to
  https://ghcr.io/v2/wilddog64/shopping-cart-basket/manifests/sha-0d8ab3ba…: 403 Forbidden
```

The `ServiceDown` alert is a **true positive**. This spec is about why the credential is bad and why
nothing noticed.

## What is NOT wrong

Every layer reports healthy, which is why this survived 11h:

```
$ kubectl -n shopping-cart-apps get secret ghcr-pull-secret
NAME               TYPE                             DATA   AGE
ghcr-pull-secret   kubernetes.io/dockerconfigjson   1      11h

$ kubectl -n shopping-cart-apps get externalsecret ghcr-pull-secret
NAME               STORE           REFRESH   STATUS         READY
ghcr-pull-secret   vault-backend   15m0s     SecretSynced   True
```

The secret exists, ESO syncs it, the Vault key is populated. `SecretSynced True` means "I copied
what Vault holds", which says nothing about whether what Vault holds can pull a package.

## Root cause — the validation proves authentication, not authorization

All three PAT loaders in `scripts/plugins/shopping_cart.sh` validate with the same probe:

```bash
_pat_http=$(curl -s -o /dev/null -w "%{http_code}" --netrc-file "${_netrc}" \
  "https://api.github.com/user" 2>/dev/null || true)
if [[ "${_pat_http}" != "200" ]]; then ... fi
```

`GET /user` returns 200 for **any** token that authenticates at all. It does not require
`read:packages`, which is the only scope GHCR actually checks. So a token with no package access
passes validation, is written to Vault as the canonical PAT, syncs cleanly, and 403s on every pull.

Measured on this host — the gh CLI token has no `read:packages`:

```
$ gh auth status
  Token scopes: 'admin:public_key', 'gist', 'read:org', 'repo'
```

## Why it is self-perpetuating, not just wrong once

`shopping_cart_load_ghcr_pat_from_gh` does not merely *use* the gh CLI token — it **persists it to
Vault**:

```bash
_ghcr_pat="${_gh_token}"
_info "[acg-up] using gh CLI token for ghcr-pull-secret"
if [[ -n "${_vault_root_token:-}" ]]; then
  curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" \
    -d "{\"data\": {\"token\": \"${_ghcr_pat}\"}}" \
    "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" >/dev/null || true
  _info "[acg-up] gh CLI token saved to Vault for future runs"
fi
```

So the scope-less `gho_` OAuth token becomes the stored credential. On the next run the Vault loader
finds it, probes `/user`, gets 200, logs `using PAT from Vault`, and never falls through to the
prompt. The fallback chain is designed to escalate to a human on a bad credential, and this defect
makes the bad credential look good at every level — the system **converges** on the broken state and
cannot self-recover.

This is the same disease as the ApplicationSet values-branch freeze, the inert `45s` `scrapeTimeout`
and the missing `alertmanager-smtp-secret`: **wired, reported green, not working.**

## Secondary defect — Vault token and PAT in argv

`scripts/plugins/shopping_cart.sh:272` and `:311-313` pass both the Vault root token and the PAT as
`curl` arguments, visible in the process table:

```bash
curl -s -H "X-Vault-Token: ${_vault_root_token}" "http://localhost:${_vault_local_port}/…"
curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" -d "{\"data\": {\"token\": \"${_ghcr_pat}\"}}" …
```

CLAUDE.md is explicit: *"Vault tokens must never appear in script arguments visible in shell history
or CI logs. Use env vars or stdin."* The same violation was just fixed in the `alertmanager-secret`
Make target; these are the remaining instances on this path. Use `-H "@headerfile"` (0600, `mktemp`)
and `--data-binary @-` on stdin, as `alertmanager-secret` now does.

## Fix

Implement exactly the four changes below. Do not refactor anything else in this file.

### Change 1 — add two shared helpers

Insert both immediately **before** `function shopping_cart_load_ghcr_pat_from_env() {`.

The authoritative check is a real GHCR token exchange plus a pull-scoped API call. `GET /user` is an
authentication check; only this proves authorization. It works for classic **and** fine-grained PATs,
which is why it, not header parsing, is the gate. Note the PAT travels via `--netrc-file` and the
bearer token via `-H "@file"` — neither may appear in argv.

```bash
function _shopping_cart_ghcr_pat_can_pull() {
  local _user="$1" _pat="$2"
  local _probe_repo="${GHCR_PROBE_REPO:-wilddog64/shopping-cart-basket}"
  local _netrc _hdr _token _http

  if [[ -z "${_user}" || -z "${_pat}" ]]; then
    return 1
  fi

  _netrc=$(mktemp) && chmod 0600 "${_netrc}"
  printf 'machine ghcr.io login %s password %s\n' "${_user}" "${_pat}" > "${_netrc}"
  _token=$(curl -s --netrc-file "${_netrc}" \
    "https://ghcr.io/token?service=ghcr.io&scope=repository:${_probe_repo}:pull" \
    | jq -r '.token // empty' 2>/dev/null || true)
  rm -f "${_netrc}"

  if [[ -z "${_token}" ]]; then
    return 1
  fi

  _hdr=$(mktemp) && chmod 0600 "${_hdr}"
  printf 'Authorization: Bearer %s\n' "${_token}" > "${_hdr}"
  _http=$(curl -s -o /dev/null -w '%{http_code}' -H "@${_hdr}" \
    "https://ghcr.io/v2/${_probe_repo}/tags/list" 2>/dev/null || true)
  rm -f "${_hdr}"

  [[ "${_http}" == "200" ]]
}
```

The Vault write is duplicated verbatim in three places and each copy puts the token in argv. Replace
all three with one helper that uses a header file and stdin:

```bash
function _shopping_cart_store_ghcr_pat_in_vault() {
  local _pat="$1"
  local _hdr _body

  if [[ -z "${_vault_root_token:-}" || -z "${_pat}" ]]; then
    return 1
  fi

  _hdr=$(mktemp) && chmod 0600 "${_hdr}"
  printf 'X-Vault-Token: %s\n' "${_vault_root_token}" > "${_hdr}"
  _body=$(mktemp) && chmod 0600 "${_body}"
  jq -n --arg token "${_pat}" '{data: {token: $token}}' > "${_body}"

  curl -s -X POST -H "@${_hdr}" --data-binary "@${_body}" \
    "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" >/dev/null || true

  rm -f "${_hdr}" "${_body}"
  return 0
}
```

`jq -n --arg` also removes a real injection bug: the old `-d "{\"data\": {\"token\": \"${_ghcr_pat}\"}}"`
produces invalid JSON if the PAT contains a quote or backslash.

### Change 2 — gate every loader on pull capability

In `shopping_cart_load_ghcr_pat_from_env`, replace:

```bash
  if [[ "${_pat_http}" != "200" ]]; then
    _info "[acg-up] GHCR_PAT env var is invalid (HTTP ${_pat_http}) — falling back to Vault"
    _ghcr_pat=""
    return 1
  fi

  _info "[acg-up] using validated GHCR_PAT from env for ghcr-pull-secret"
  return 0
```

with:

```bash
  if [[ "${_pat_http}" != "200" ]]; then
    _info "[acg-up] GHCR_PAT env var is invalid (HTTP ${_pat_http}) — falling back to Vault"
    _ghcr_pat=""
    return 1
  fi

  if ! _shopping_cart_ghcr_pat_can_pull "${_github_user}" "${_ghcr_pat}"; then
    _info "[acg-up] GHCR_PAT env var authenticates but cannot pull from ghcr.io — it is missing the read:packages scope; image pulls would 403. Falling back to Vault"
    _ghcr_pat=""
    return 1
  fi

  _info "[acg-up] using validated GHCR_PAT from env for ghcr-pull-secret"
  return 0
```

In `shopping_cart_load_ghcr_pat_from_vault`, replace:

```bash
  if [[ "${_pat_http}" != "200" ]]; then
    _info "[acg-up] Vault PAT is expired (HTTP ${_pat_http}) — prompting for a new one"
    _ghcr_pat=""
    return 1
  fi

  _info "[acg-up] using PAT from Vault for ghcr-pull-secret"
  return 0
```

with:

```bash
  if [[ "${_pat_http}" != "200" ]]; then
    _info "[acg-up] Vault PAT is expired (HTTP ${_pat_http}) — prompting for a new one"
    _ghcr_pat=""
    return 1
  fi

  if ! _shopping_cart_ghcr_pat_can_pull "${_github_user}" "${_ghcr_pat}"; then
    _info "[acg-up] Vault PAT authenticates but cannot pull from ghcr.io — it is missing the read:packages scope; mint a PAT with read:packages and overwrite secret/github/pat"
    _ghcr_pat=""
    return 1
  fi

  _info "[acg-up] using PAT from Vault for ghcr-pull-secret"
  return 0
```

Also replace the Vault read on the line beginning `_ghcr_pat=$(curl -s -H "X-Vault-Token: ...` with a
header-file form so the token leaves argv:

```bash
  local _vault_hdr
  _vault_hdr=$(mktemp) && chmod 0600 "${_vault_hdr}"
  printf 'X-Vault-Token: %s\n' "${_vault_root_token}" > "${_vault_hdr}"
  _ghcr_pat=$(curl -s -H "@${_vault_hdr}" \
    "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" \
    | jq -r '.data.data.token // empty' 2>/dev/null || true)
  rm -f "${_vault_hdr}"
```

### Change 3 — never persist a credential that cannot pull

This is the change that makes the bug recoverable. In `shopping_cart_load_ghcr_pat_from_gh`, replace:

```bash
  if ! GH_TOKEN="${_gh_token}" gh api user >/dev/null 2>&1; then
    return 1
  fi

  _ghcr_pat="${_gh_token}"
  _info "[acg-up] using gh CLI token for ghcr-pull-secret"
  if [[ -n "${_vault_root_token:-}" ]]; then
    curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" \
      -d "{\"data\": {\"token\": \"${_ghcr_pat}\"}}" \
      "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" >/dev/null || true
    _info "[acg-up] gh CLI token saved to Vault for future runs"
  fi
  return 0
```

with:

```bash
  if ! GH_TOKEN="${_gh_token}" gh api user >/dev/null 2>&1; then
    return 1
  fi

  if ! _shopping_cart_ghcr_pat_can_pull "${_github_user}" "${_gh_token}"; then
    _info "[acg-up] gh CLI token cannot pull from ghcr.io — its OAuth scopes are fixed and exclude read:packages, so it is NOT being saved to Vault"
    return 1
  fi

  _ghcr_pat="${_gh_token}"
  _info "[acg-up] using gh CLI token for ghcr-pull-secret"
  if _shopping_cart_store_ghcr_pat_in_vault "${_ghcr_pat}"; then
    _info "[acg-up] gh CLI token saved to Vault for future runs"
  fi
  return 0
```

In `shopping_cart_prompt_ghcr_pat`, replace:

```bash
  if [[ -n "${_vault_root_token:-}" ]]; then
    curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" \
      -d "{\"data\": {\"token\": \"${_ghcr_pat}\"}}" \
      "http://localhost:${_vault_local_port}/v1/secret/data/github/pat" >/dev/null || true
    _info "[acg-up] new PAT saved to Vault"
  fi
  return 0
```

with:

```bash
  if ! _shopping_cart_ghcr_pat_can_pull "${_github_user}" "${_ghcr_pat}"; then
    _err "[acg-up] the pasted PAT cannot pull from ghcr.io — it is missing the read:packages scope; not saving it to Vault"
    _ghcr_pat=""
    return 1
  fi

  if _shopping_cart_store_ghcr_pat_in_vault "${_ghcr_pat}"; then
    _info "[acg-up] new PAT saved to Vault"
  fi
  return 0
```

Note the prompt path previously stored the pasted value with **no validation at all** — not even
`GET /user`. That is the third instance of persist-before-verify.

### Change 4 — BATS coverage

Add to `scripts/tests/plugins/shopping_cart.bats`, matching the existing source-and-stub style
(source `scripts/lib/system.sh`, `scripts/lib/core.sh`, then the plugin, and stub `curl`/`jq`/`gh`
as needed). Cover:

1. `_shopping_cart_ghcr_pat_can_pull` returns 0 when the token exchange yields a token and
   `tags/list` returns `200`.
2. It returns non-zero when `tags/list` returns `403` — the missing-`read:packages` case.
3. It returns non-zero when the token exchange yields an empty token.
4. `shopping_cart_load_ghcr_pat_from_gh` does **not** call the Vault write when the pull probe fails,
   and its message mentions `read:packages`. Assert the Vault write did not happen by having the
   stub append to a temp file and asserting that file stays empty — this is the regression that
   matters most.
5. Neither the PAT nor the Vault token appears in any `curl` argv: assert the source contains no
   `-H "X-Vault-Token: ` and no `-d "{\"data\"` on this path. Prefer a disappearance gate
   (old pattern → 0 matches) over counting.

Do not assert against whole source lines — assert on meaningful tokens only.

## Rules

- `set -euo pipefail` semantics are already established in this file; do not weaken them.
- Double-quote every expansion. Run `shellcheck scripts/plugins/shopping_cart.sh` and finish with
  **zero new warnings** versus the pre-change baseline. Capture the baseline first.
- Run `bats scripts/tests/plugins/shopping_cart.bats` and paste the actual output. `bats` is bare on
  PATH at `/opt/homebrew/bin/bats`.
- Do NOT run the full `make test` — it takes ~15 minutes and is not required here.
- No inline comments in the shell blocks.
- LF line endings only.
- Minimal patch: only `scripts/plugins/shopping_cart.sh` and
  `scripts/tests/plugins/shopping_cart.bats` may change.

## Operator action required (cannot be automated)

The gh CLI token cannot be used — its scopes are fixed by the OAuth app and it has no
`read:packages`. The operator must mint a PAT with `read:packages`, then overwrite
`secret/github/pat` in Vault, force-sync `ghcr-pull-secret`, and restart the four deployments. This
is a routine operator step, not a blocker.

## Definition of Done

- [ ] `_shopping_cart_ghcr_pat_can_pull` added and gating all four loaders
- [ ] `_shopping_cart_store_ghcr_pat_in_vault` added and replacing all three duplicated Vault writes
- [ ] No loader persists a credential that has not passed the pull probe
- [ ] `shopping_cart_prompt_ghcr_pat` validates before storing (it previously did not validate at all)
- [ ] Failure messages name `read:packages` and the remedy
- [ ] Vault root token and PAT no longer appear in `curl` argv anywhere on this path
- [ ] PAT is JSON-encoded with `jq -n --arg`, not string-interpolated into a JSON literal
- [ ] `shellcheck scripts/plugins/shopping_cart.sh` — zero new warnings vs the captured baseline
- [ ] `bats scripts/tests/plugins/shopping_cart.bats` green, output pasted
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the commit SHA and
      task status
- [ ] Commit pushed to `origin/k3d-manager-v1.36.0` and `git rev-parse origin/k3d-manager-v1.36.0`
      confirms it

Deferred to the operator, explicitly **out of scope** for this task:

- [ ] Live: a PAT with `read:packages` written to Vault, and the four `shopping-cart-apps`
      deployments Running with `ServiceDown` resolved

### Commit message (use verbatim)

```
fix(shopping-cart): validate the GHCR PAT can pull, not merely authenticate

All three PAT loaders gated on GET https://api.github.com/user, which returns
200 for any token that authenticates and never checks read:packages — the only
scope GHCR enforces. A scope-less token therefore passed validation, and
shopping_cart_load_ghcr_pat_from_gh persisted it to secret/github/pat, so the
Vault loader later found it, probed /user, got 200, and never escalated to the
operator prompt. The fallback chain converged on a permanently broken credential
with ESO, ArgoCD and the validation all reporting green while every image pull
403'd.

Every loader now gates on a real GHCR token exchange plus a pull-scoped
tags/list call, which is authoritative for both classic and fine-grained PATs.
No loader persists a credential that has not passed that probe, so a bad
credential can no longer become the stored PAT. shopping_cart_prompt_ghcr_pat
previously stored the pasted value with no validation whatsoever.

The three duplicated Vault writes collapse into one helper that passes the token
by header file and the body on stdin, per the CLAUDE.md rule that Vault tokens
must never appear in argv, and encodes the PAT with jq -n --arg instead of
interpolating it into a JSON string literal.
```

Report back: the commit SHA, the `bats` output, the shellcheck before/after counts, and the
memory-bank lines you updated.

## What NOT to Do

- Do NOT treat `SecretSynced True` as evidence the credential works. It only means ESO copied what
  Vault holds.
- Do NOT keep `GET /user` as the sole gate. It is an authentication check being used as an
  authorization check.
- Do NOT reject a PAT because `X-OAuth-Scopes` is empty — that is the normal shape for a
  fine-grained PAT.
- Do NOT persist the gh CLI token to Vault before it has proven it can pull; that is what makes this
  bug unrecoverable without manual intervention.
- Do NOT pass the Vault token or the PAT as `curl` arguments.
- Do NOT create a PR.
- Do NOT merge, and do NOT commit to `main` — work only on `k3d-manager-v1.36.0`.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT force-push.
- Do NOT modify any file outside `scripts/plugins/shopping_cart.sh`,
  `scripts/tests/plugins/shopping_cart.bats` and the two memory-bank files.
- Do NOT touch the live cluster, Vault, or the credential itself — code and tests only.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/`; they are subtrees, fixed upstream.
- Do NOT run the full `make test`.
