# Bug: a Vault rebuild leaves Prometheus and ArgoCD credentials permanently unseeded, and every consumer degrades silently

**Filed:** 2026-09-21
**Branch:** `k3d-manager-v1.36.0`
**Status:** OPEN
**Targets:** `scripts/plugins/observability.sh`, `Makefile` (`show-service-passwords`)
**Follows:** `docs/bugs/2026-09-21-show-service-passwords-liveness-probe-uses-optional-kv-path.md` (`ef3d4b8d`)

---

## Problem

With the liveness gate fixed, `make show-service-passwords` now runs to completion — and shows
that two of four credentials are unreachable:

```
  ArgoCD      password: N/A
  Grafana     password: <present>
  Prometheus  password: N/A
  Alertmanager password: <present>
```

Both `N/A`s are real gaps in Vault, not display bugs.

### What is actually missing

Probed `127.0.0.1:18200` on hub `k3d-k3d-cluster`, 2026-09-21 (status codes only, no values):

| Path | data | **metadata** |
|---|---|---|
| `secret/data/observability/grafana` | 200 | — |
| `secret/data/k3d-manager/alertmanager-basic-auth` | 200 | **200** |
| `secret/data/k3d-manager/prometheus-basic-auth` | **404** | **404** |
| `secret/data/argocd/admin` | **404** | **404** |

**The metadata 404 is the decisive evidence.** In KV v2, deleting a secret's *data* leaves its
metadata and version history intact; only `DELETE secret/metadata/<path>` (destroy-all) removes
metadata, and no code path in this repo ever calls that. So these two paths were **never written
to the current Vault instance** — this is not deletion and not corruption.

The surviving `k3d-manager/alertmanager-basic-auth` was created at **2026-09-21T01:42:57Z**, while
`vault-0` started at **2026-09-20T23:46:10Z** and `argocd-secret.admin.passwordMtime` is
**2026-09-20T23:51:56Z**. The hub was rebuilt that evening; everything in Vault today was written
*after* the rebuild. Re-seeding was **partial**: Grafana and Alertmanager were reseeded, Prometheus
and ArgoCD were not.

### Why nobody noticed

`_observability_ensure_prometheus_login` (`scripts/plugins/observability.sh:268`) is **read-only
against Vault**. On a 404 it warns and gives up — it never reseeds:

```bash
  if [[ -z "${_prom_creds}" ]]; then
    _warn "[observability] Prometheus Vault credentials unreadable — skipping auth proxy"
    return 1
  fi
```

and its sole caller swallows that failure outright (`observability.sh:451`):

```bash
function _observability_refresh_prometheus_auth_proxy() {
  _observability_ensure_prometheus_login || return 0
```

So a missing canonical credential is a `_warn` on a path whose return code is discarded. This is
the long-standing **"Prometheus Vault credentials unreadable"** backlog item — now root-caused.

Meanwhile the Prometheus login still *works* for the operator, which hid the gap completely:
`bin/prometheus-auth-proxy` runs host-side on `:19090` with
`--credentials-file ~/.local/share/k3d-manager/prometheus-basic-auth.env`. That file is a
**derived cache** written by `_observability_ensure_prometheus_login` from a *previous* Vault
instance; it survived the rebuild because it lives on the host, not in the cluster. The proxy
validates logins against that same file, so the loop is self-consistent and green
(verified: `https://prometheus.3ai-talk.org/api/v1/status/buildinfo` → **200** with the file's
credential, **401** anonymous) while the canonical store behind it is empty.

**Consequence:** the only surviving copy of the Prometheus password is an undocumented host-side
cache file. A laptop reimage, or any code path that regenerates it, loses the credential with no
warning. `make show-service-passwords` cannot report it, and `bin/k3dm-webhook:2113` smoke-tests
it from Vault, so that check is degraded too.

---

## Fix

**Do not "fix" this by making `show-service-passwords` read the env file for Prometheus.**
`docs/bugs/2026-06-09-prometheus-basic-auth-vault-managed.md` deliberately made Vault the
canonical source of truth for this credential; a display-time file fallback would reverse that
decision and entrench the cache as a second source of truth. The repair belongs in the seeding
path.

The two services need **opposite** fixes, because their authoritative stores differ:

| Service | Authoritative store | Vault's role | Correct fix |
|---|---|---|---|
| Prometheus | **Vault** (per 2026-06-09) | canonical | reseed Vault; keep display Vault-only |
| ArgoCD | **`cicd/argocd-initial-admin-secret`** (ArgoCD owns it) | display *mirror* | display may read the k8s secret |

### M1 — reseed Vault instead of giving up (`scripts/plugins/observability.sh`)

In `_observability_ensure_prometheus_login`, replace the bare `_warn` + `return 1` on an
unreadable Vault path with a reseed. **Prefer the surviving cache file when it is usable**, so a
rebuild does not silently rotate a credential the operator already has saved; only generate a new
password when there is nothing to recover.

Replace:

```bash
  if [[ -z "${_prom_creds}" ]]; then
    _warn "[observability] Prometheus Vault credentials unreadable — skipping auth proxy"
    return 1
  fi
```

with:

```bash
  if [[ -z "${_prom_creds}" ]]; then
    _warn "[observability] Prometheus credentials absent from Vault — reseeding the canonical entry"
    local _recovered_user="" _recovered_password=""
    if [[ -r "${_auth_file}" ]]; then
      _recovered_user=$(sed -n 's/^PROMETHEUS_BASIC_AUTH_USER=//p' "${_auth_file}" | head -1)
      _recovered_password=$(sed -n 's/^PROMETHEUS_BASIC_AUTH_PASSWORD=//p' "${_auth_file}" | head -1)
    fi
    if [[ -n "${_recovered_password}" && "${_recovered_password}" != "password" ]]; then
      _PROM_BASIC_AUTH_PASSWORD="${_recovered_password}"
      _PROM_BASIC_AUTH_BCRYPT="$(printf '%s' "${_PROM_BASIC_AUTH_PASSWORD}" | htpasswd -niBC 12 admin | cut -d: -f2-)"
      [[ -n "${_PROM_BASIC_AUTH_BCRYPT}" ]] || { _err "[observability] failed to rebcrypt the recovered Prometheus password"; return 1; }
      _info "[observability] recovered the Prometheus password from the local cache; not rotating"
    else
      _observability_generate_prometheus_basic_auth || return 1
      _warn "[observability] no recoverable Prometheus password — generated a new one; saved logins will stop working"
    fi
    if ! _observability_seed_prometheus_vault_entry; then
      _err "[observability] could not reseed k3d-manager/prometheus-basic-auth in Vault"
      return 1
    fi
    _prom_creds="${_recovered_user:-admin}|${_PROM_BASIC_AUTH_PASSWORD}"
  fi
```

Add the small helper beside it (reusing the existing payload builder, so the bcrypt and plaintext
stay in one shape):

```bash
function _observability_seed_prometheus_vault_entry() {
  local _vault_addr="http://127.0.0.1:18200" _vault_token _vault_hdr _payload _rc=0
  _vault_token=$(_kubectl get secret vault-root -n secrets \
    --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' | base64 --decode)
  _vault_hdr=$(mktemp)
  printf 'X-Vault-Token: %s\n' "${_vault_token}" > "${_vault_hdr}"
  _payload=$(_observability_prometheus_vault_payload "${_PROM_BASIC_AUTH_PASSWORD}" "${_PROM_BASIC_AUTH_BCRYPT}")
  curl -sf --header "@${_vault_hdr}" --header 'Content-Type: application/json' \
    --request POST --data "${_payload}" \
    "${_vault_addr}/v1/secret/data/k3d-manager/prometheus-basic-auth" >/dev/null || _rc=1
  rm -f "${_vault_hdr}"
  return "${_rc}"
}
```

Keep the token in a `mktemp` header file and delete it on every exit path — never in argv.

### M2 — stop discarding the failure (`scripts/plugins/observability.sh:451`)

`_observability_refresh_prometheus_auth_proxy` must not convert a seeding failure into success:

Old:
```bash
  _observability_ensure_prometheus_login || return 0
```

New:
```bash
  if ! _observability_ensure_prometheus_login; then
    _warn "[observability] Prometheus login unavailable; auth proxy not refreshed"
    return 1
  fi
```

Check each caller of `_observability_refresh_prometheus_auth_proxy` (`observability.sh:112`, `:598`,
`:800`) still behaves sensibly with a non-zero return — this must surface the problem, **not**
abort an otherwise healthy deploy. If a caller runs under `set -e` in a position where a non-zero
return would abort the deploy, append `|| true` **at that call site** with a one-line justification
in the commit body, rather than re-hiding it inside the function.

### M3 — ArgoCD display falls back to the authoritative k8s secret (`Makefile`)

In the ArgoCD credential block only, when the Vault mirror read yields nothing, fall back to the
secret ArgoCD itself owns. This is reading the *authoritative* store, not adding a second one:

```make
	_argocd=$$(curl -sf -H "@$$_vault_hdr" \
	  "http://127.0.0.1:18200/v1/secret/data/argocd/admin" 2>/dev/null | \
	  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["data"].get("password","N/A"))' 2>/dev/null || true); \
	rm -f "$$_vault_hdr"; \
	[ -n "$$_argocd" ] || _argocd=$$(kubectl get secret argocd-initial-admin-secret -n cicd \
	  --context k3d-k3d-cluster -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || true); \
```

Leave the `$${_argocd:-N/A}` default in place — if both sources are empty, `N/A` is still correct.
Do **not** add a file or k8s fallback to the Prometheus block.

### M4 — document the rebuild gap (`docs/howto/` or `docs/guides/`)

One short subsection: after a Vault rebuild, credential paths are **not** all reseeded
automatically; `secret/argocd/admin` is repopulated by `hub_recovery_reconcile` and
`k3d-manager/prometheus-basic-auth` by the Prometheus auth-proxy refresh. Note that
`~/.local/share/k3d-manager/prometheus-basic-auth.env` is a derived cache, not a source of truth.

---

## Tests

### `scripts/tests/plugins/observability_prometheus_reseed.bats` (new)

There is **no** `observability.bats` — this suite uses one focused file per concern
(`observability_grafana_seed.bats`, `observability_hub_ordering.bats`, …). Add a new file and
follow the idiom in `scripts/tests/plugins/observability_grafana_seed.bats` exactly:

```bash
setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
}
```

then override collaborators as shell functions inside each `@test`, appending to
`"$BATS_TEST_TMPDIR/calls"`. Stub `_kubectl`, `curl`, `htpasswd` and
`_observability_prometheus_vault_payload`. Point the auth file at `BATS_TEST_TMPDIR` by overriding
`_observability_prometheus_auth_file` — never touch `$HOME`.

1. Vault read returns a credential → **no** reseed POST is issued (the healthy path must not write).
2. Vault 404 **and** a readable cache file with a strong password → a POST to
   `secret/data/k3d-manager/prometheus-basic-auth` is issued, and the password sent is the one from
   the cache file (assert the *recovered* value is reused, i.e. no rotation).
3. Vault 404 and **no** cache file → `_observability_generate_prometheus_basic_auth` is called and a
   POST is still issued.
4. Vault 404 and a cache file containing the literal `password` → treated as unusable, a fresh
   credential is generated (guards the `_PROM_WEAK_BCRYPT` intent already in the codebase).
5. Vault 404 and the reseed POST fails → `_observability_ensure_prometheus_login` returns **non-zero**
   and `_observability_refresh_prometheus_auth_proxy` also returns **non-zero** (M2's whole point).

Assert the recorded call log never contains the stub password value, and never contains the Vault
token.

### `scripts/tests/bin/makefile_show_service_passwords.bats` (extend)

Reuse the existing `show_service_passwords_target` helper and per-service block extraction.

6. The **ArgoCD** block references `argocd-initial-admin-secret`.
7. The **Prometheus** block does **not** reference `prometheus-basic-auth.env` and does not
   reference `argocd-initial-admin-secret` — the asymmetry is deliberate and must be pinned, or a
   later "make it consistent" refactor will silently undo the 2026-06-09 decision.
8. All four blocks still contain `:-N/A}` (keep the existing assertion green).

**Mutation check (mandatory, per `reference_new_test_passing_does_not_mean_it_can_fail`):** run
tests 6–7 against the **pre-fix** `Makefile` — use `git show HEAD:Makefile > <scratchpad>/pre.mk`
and point `MAKEFILE` at it. **`git stash` is forbidden.** Test 6 must **fail** pre-fix. Paste the
output. Note test 7 is expected to *pass* pre-fix (it asserts an absence) — say so explicitly
rather than presenting it as proof.

---

## Definition of Done

- [ ] M1–M4 implemented; no files touched outside `scripts/plugins/observability.sh`, `Makefile`,
      the two BATS files, one doc file and `CHANGELOG.md`
- [ ] `shellcheck -x scripts/plugins/observability.sh` — rc 0
- [ ] `bats scripts/tests/plugins/observability_prometheus_reseed.bats scripts/tests/bin/makefile_show_service_passwords.bats` green — paste the summary
- [ ] Mutation check output pasted, with test 6 red pre-fix and test 7's expected pre-fix pass called out
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "a Vault rebuild no longer leaves `k3d-manager/prometheus-basic-auth` permanently unseeded — the auth-proxy refresh reseeds the canonical entry, recovering the existing password from the local cache rather than rotating it, and `show-service-passwords` falls back to `argocd-initial-admin-secret` for the ArgoCD display"
- [ ] Commit message verbatim: `fix(observability): reseed the canonical Prometheus credential after a Vault rebuild`
- [ ] Pushed to `origin/k3d-manager-v1.36.0`; report the SHA and confirm with `git rev-parse origin/k3d-manager-v1.36.0`

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`
- Do NOT run anything against the live cluster, Vault, ArgoCD, Prometheus or any port-forward.
  This is a source-only change with stubbed tests. **Do NOT reseed the real Vault** — the operator
  decides when to run the repair.
- Do NOT rotate, regenerate or overwrite any live credential, and do NOT call
  `observability_rotate_prometheus_basic_auth`
- Do NOT read, print or echo the Vault root token or any password, and do NOT place either in argv
- Do NOT add a file-based or k8s-based fallback to the **Prometheus** display block — that reverses
  `docs/bugs/2026-06-09-prometheus-basic-auth-vault-managed.md`
- Do NOT delete or rewrite `~/.local/share/k3d-manager/prometheus-basic-auth.env`, and do NOT have
  the tests touch `$HOME` — use `BATS_TEST_TMPDIR`
- Do NOT modify `scripts/lib/foundation/` or `scripts/lib/acg/`
- Do NOT `git add -A` and do NOT `git stash`
