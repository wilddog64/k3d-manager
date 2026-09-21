# GHCR PAT is validated for authentication but never for `read:packages`, so the system converges on a permanently broken pull credential

**Filed:** 2026-09-21
**Branch:** `k3d-manager-v1.36.0`
**Severity:** High — every private image pull on the hub 403s while ESO, ArgoCD and the PAT
validation all report green.
**Status:** Open

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

**1 — Validate the scope, not just the token.** GitHub returns the granted scopes in a response
header, so this costs nothing extra:

```bash
_scopes=$(curl -s -D - -o /dev/null --netrc-file "${_netrc}" "https://api.github.com/user" \
  | tr -d '\r' | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}')
```

Require `read:packages` (or `write:packages`, which implies it). Note fine-grained PATs return an
**empty** `X-OAuth-Scopes`, so an empty value must not be treated as failure — fall through to the
authoritative check below rather than rejecting.

**2 — Prefer an end-to-end probe over header parsing.** The only check that cannot be wrong is a real
token exchange plus manifest HEAD against GHCR:

```
GET https://ghcr.io/token?service=ghcr.io&scope=repository:<owner>/<repo>:pull   (Basic auth)
HEAD https://ghcr.io/v2/<owner>/<repo>/manifests/<tag>                           (Bearer)
```

A 200 on the HEAD is the definition of "this credential can pull". This works for both classic and
fine-grained PATs and is the check the validation should have been doing all along.

**3 — Never persist an unvalidated credential.** Move the Vault write in
`shopping_cart_load_ghcr_pat_from_gh` to *after* the pull probe passes. A credential that cannot pull
must never become the stored PAT, or the fallback chain can never escalate to the operator.

**4 — Make the failure legible.** On a scope failure the message must name the missing scope and the
remedy, e.g. `GHCR PAT authenticates but lacks read:packages — pulls will 403; supply a PAT with
read:packages`. `HTTP 200` followed 11h later by `403 Forbidden` in kubelet logs is not a diagnosis.

**5 — Move the Vault token and PAT out of argv** per the secondary defect above.

## Operator action required (cannot be automated)

The gh CLI token cannot be used — its scopes are fixed by the OAuth app and it has no
`read:packages`. The operator must mint a PAT with `read:packages`, then overwrite
`secret/github/pat` in Vault, force-sync `ghcr-pull-secret`, and restart the four deployments. This
is a routine operator step, not a blocker.

## Definition of Done

- [ ] PAT validation requires package-pull capability, not just `GET /user` 200
- [ ] Empty `X-OAuth-Scopes` (fine-grained PAT) is not treated as a failure
- [ ] The gh CLI token is written to Vault only after it proves it can pull
- [ ] Failure message names the missing scope and the remedy
- [ ] Vault root token and PAT no longer appear in `curl` argv on this path
- [ ] BATS covers: valid classic PAT, authenticating token without `read:packages`, fine-grained PAT
      with empty scopes header, and the no-persist-on-failure path
- [ ] Live: four `shopping-cart-apps` deployments Running and `ServiceDown` resolved

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
