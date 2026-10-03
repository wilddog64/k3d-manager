# Bug: `make up` Keycloak steps target the wrong component, and frontendUrl never applies

**Filed:** 2026-10-03, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN
**Severity:** medium. SSO works today only because `hub_recovery_reconcile` (the smoke path)
repairs what `make up` gets wrong. Every `make up` prints three SSO warnings that look like an
outage. It also leaves a stray Keycloak component behind, and that component throws an NPE
on every sync.

## Observed (2026-10-03, sandbox `make up`, exit 0)

```
WARN: [acg-up] Keycloak frontendUrl update failed — external SSO may not work
WARN: [acg-up] LDAP bind credential reconciliation failed — SSO login may be broken
INFO: [acg-up] LDAP group mapper created
WARN: [acg-up] LDAP group sync failed
```

The frontendUrl warning also appears in the 2026-07-07 log, quoted in
`docs/issues/2026-07-07-shopping-cart-rerun-ldap-password-seed-vault-helper-scope.md`. It recurs;
it is not a one-off.

Live evidence, all read-only:

- In the `shopping-cart` realm, the LDAP provider is `a5a37610` (`providerId: ldap`). Two
  components are named `group-mapper`:
  - `b7eb43f7`, whose parent is `a5a37610`. This one is correct.
  - `9233ebab`, whose parent is `398e5ed4`, the **"full name" mapper** (`full-name-ldap-mapper`).
    This is the stray one, created by this run.
- At 20:41:35 UTC, the Keycloak log shows: `NullPointerException: Cannot invoke
  "LDAPStorageProvider.getSession()" because "ldapProvider" is null`, inside
  `GroupLDAPStorageMapper.<init>`. This is the 10d.7 sync running against the stray mapper.
- The full syncs on the real provider succeed, at 20:45, 20:49 and 20:56 (`5 updated users`).
- The realm issuer is `https://keycloak.3ai-talk.org/realms/shopping-cart`. That is correct, but
  `keycloak.sh` `_keycloak_smoke_ensure_realm` set it. `make up` did not.
- The "full name" mapper has no `bindCredential` key. The misdirected 10d.6 update was rejected,
  so no secret was stored on it.

## Root cause

1. **Wrong component ID, in 10d.6 and in the 10d.7 fallback.** Both run
   `kcadm get components --fields id,providerId | grep -B1 'ldap' | grep '"id"' | head -1`.
   Every LDAP mapper has a `providerId` that contains `ldap`, such as `full-name-ldap-mapper`
   or `user-attribute-ldap-mapper`. So the first match can be a **mapper**. Once a realm is
   imported with its mappers, it usually is one.
   - In 10d.6, `update components/<mapper>` and `triggerFullSync` fail, which gives the WARN.
   - 10d.7 then creates `group-mapper` with the mapper as its parent ("created"), and its sync
     hits the NPE, which gives the WARN.
2. **frontendUrl is sent as a top-level field.** `bin/cluster-up` PUTs
   `{"frontendUrl":"..."}`. `RealmRepresentation` has no such field. The setting lives in
   `attributes.frontendUrl`, which is the field `_keycloak_smoke_ensure_realm` already writes
   with GET → merge → PUT. `curl -sf` hides the status code, so the warning carries no cause.
3. **Secrets in `kubectl exec` command strings.** The 10d.6 lookup and update, and the 10d.7
   fallback, interpolate `${_kc_admin_pass}` and `${_ldap_admin_pass}` into `sh -c "..."`.
   That breaks the CLAUDE.md rule "No secrets in `kubectl exec` command strings". The 10d.6
   create branch already avoids this.

## Fix (Codex)

Target files: `bin/cluster-up` and `scripts/tests/bin/cluster_up.bats`. Nothing else.

**F1. Add one helper**, placed next to the other `function _acg_*` helpers near the top of
`bin/cluster-up`:

```bash
function _acg_keycloak_ldap_provider_id() {
  local kc_pod="$1" kc_admin_pass="$2"
  printf '%s\n' "${kc_admin_pass}" | \
    kubectl exec -i -n identity --context k3d-k3d-cluster "${kc_pod}" -- sh -c '
      read -r KC_ADMIN_PASS
      K=/opt/keycloak/bin/kcadm.sh
      "$K" config credentials --server http://localhost:8080 --realm master \
        --user admin --password "$KC_ADMIN_PASS" >/dev/null 2>&1 || exit 1
      "$K" get components -r shopping-cart \
        -q type=org.keycloak.storage.UserStorageProvider \
        --fields id,providerId --format csv --noquotes 2>/dev/null' 2>/dev/null | \
    while IFS=, read -r _id _provider; do
      if [[ "${_provider}" == "ldap" ]]; then printf '%s\n' "${_id}"; break; fi
    done
}
```

This selects the component by **type** `UserStorageProvider` plus `providerId == ldap`, never
by a substring of `providerId`. The password goes over stdin.

**F2. Step 10d.6.** Replace the inline `_ldap_component_id=$(kubectl exec ... grep -B1 'ldap' ...)`
with `_ldap_component_id=$(_acg_keycloak_ldap_provider_id "${_kc_pod}" "${_kc_admin_pass}" || true)`.
Replace the update + `triggerFullSync` exec with a stdin form that keeps both secrets out of
argv:

```bash
      printf '%s\n%s\n' "${_kc_admin_pass}" "${_ldap_admin_pass}" | \
        kubectl exec -i -n identity --context k3d-k3d-cluster "${_kc_pod}" -- sh -c '
          read -r KC_ADMIN_PASS
          read -r LDAP_BIND
          K=/opt/keycloak/bin/kcadm.sh
          "$K" config credentials --server http://localhost:8080 --realm master \
            --user admin --password "$KC_ADMIN_PASS" >/dev/null 2>&1 || exit 1
          "$K" update "components/$1" -r shopping-cart \
            -s "config.bindCredential=[\"$LDAP_BIND\"]" >/dev/null 2>&1 && \
          "$K" create "user-storage/$1/sync?action=triggerFullSync" -r shopping-cart >/dev/null 2>&1
        ' _ "${_ldap_component_id}" 2>/dev/null && \
        _info "[acg-up] LDAP federation bind credential reconciled and full sync triggered" || \
        _warn "[acg-up] LDAP bind credential reconciliation failed — SSO login may be broken"
```

Leave the create branch (component absent) unchanged.

**F3. Step 10d.7.**
- Replace the fallback lookup (`if [[ -z "${_ldap_component_id:-}" && -n "${_kc_pod:-}" ]]`) with
  the helper.
- Before the `_gm_existing` check, delete every `group-mapper` LDAPStorageMapper whose
  `parentId` is not `${_ldap_component_id}`. This removes the stray from earlier runs, including
  the live `9233ebab`.

```bash
    kubectl exec -n identity --context k3d-k3d-cluster "${_kc_pod}" -- sh -c '
      K=/opt/keycloak/bin/kcadm.sh
      "$K" get components -r shopping-cart -q name=group-mapper \
        --fields id,parentId,providerId --format csv --noquotes 2>/dev/null | \
      while IFS=, read -r id parent provider; do
        [ "$provider" = "group-ldap-mapper" ] && [ -n "$id" ] && [ "$parent" != "$1" ] && \
          "$K" delete "components/$id" -r shopping-cart >/dev/null 2>&1
      done; exit 0' _ "${_ldap_component_id}" 2>/dev/null || true
```

Query by `name` only. A live check on 2026-10-03, read-only on Keycloak 24, showed that
`-q type=...LDAPStorageMapper` **without** `-q parent=` returns nothing, because Keycloak
defaults the parent to the realm. `-q name=group-mapper` alone returns both mappers:
`b7eb43f7,a5a37610…` and `9233ebab,398e5ed4…`.

This relies on the kcadm session that 10d.6 writes in the pod, the same as the existing 10d.7
calls do.

**F4. frontendUrl (10d).** Replace the `curl -sf -X PUT ... -d "{\"frontendUrl\":...}"` block with
the existing keycloak.sh helper. It does GET → merge `attributes.frontendUrl` → PUT:

```bash
    _kc_frontend_url="${KEYCLOAK_PUBLIC_URL:-https://keycloak.3ai-talk.org}"
    _kc_realm_wd="$(mktemp -d)"
    if _keycloak_smoke_ensure_realm "http://localhost:${_kc_pf_port}" "${_kc_token}" \
         "shopping-cart" "${_kc_frontend_url}" "${_kc_realm_wd}"; then
      _info "[acg-up] Keycloak frontendUrl set to ${_kc_frontend_url}"
    else
      _warn "[acg-up] Keycloak frontendUrl update failed — external SSO may not work"
    fi
    rm -rf "${_kc_realm_wd}"
```

`bin/cluster-up` already sources `scripts/plugins/keycloak.sh`. Confirm that `_curl` and `jq` are
available in that context. If `_curl` is not defined there, stop and report; do not add a shim.

## Gates (offline; stubs only; no live cluster)

- **BATS, behavior:** extract `_acg_keycloak_ldap_provider_id` with
  `sed -n '/function _acg_keycloak_ldap_provider_id/,/^}/p'`. Use a `kubectl` stub that prints the
  CSV `398e5ed4,full-name-ldap-mapper` and then `a5a37610,ldap`. The helper must print
  `a5a37610`. The stub must also record its argv. Assert that the password value is **not** in
  argv but **is** on stdin.
- **BATS, source:** the string `grep -B1 'ldap'` no longer occurs in `bin/cluster-up` (a
  disappearance gate, run with `run grep`; status ≠ 0). No `--password '${_kc_admin_pass}'` and no
  `bindCredential=[\"${_ldap_admin_pass}` remain.
- **BATS, source:** the 10d.7 block (`sed -n "/Step 10d.7\/14/,/step-10d7-group-mapper/p"`)
  contains `"$parent" != "$1"`, `group-ldap-mapper` and `delete "components/$id"`. The 10d block calls
  `_keycloak_smoke_ensure_realm` and no longer contains `{\"frontendUrl\"`.
- **Mutation:** put the `grep -B1 'ldap'` selection back into the helper (snapshot with `cp`, then
  restore and `cmp`; never `git checkout`). The behavior test must go red.
- `shellcheck bin/cluster-up` adds no new warnings. `bats scripts/tests/bin/cluster_up.bats` is
  all green. `git diff --stat` shows only the two target files.

## Live verification (Claude, next sandbox `make up`)

- `make up` prints `LDAP federation bind credential reconciled`, `LDAP group sync complete` and
  `Keycloak frontendUrl set to`, with no SSO WARNs.
- Keycloak components: exactly one `group-mapper`, with parent = the `ldap` provider; `9233ebab`
  is gone.
- The Keycloak log has no `ldapProvider is null` after the run.

## Workaround

None is needed for logins. The real provider binds and syncs, and the issuer is correct after
`hub_recovery_reconcile`. The stray mapper only adds an NPE to the log on each 10d.7 sync.
