# Bug: `make up` writes the wrong LDAP bind password into Keycloak (regression exposed by `fd3616fd`)

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN. The live hub bind was repaired by the operator on 2026-10-04. Code fix `cc81df52` (Codex; Claude-verified). Live check on the next sandbox `make up`.
**Parent:** `docs/bugs/2026-10-03-cluster-up-keycloak-ldap-component-lookup-picks-a-mapper.md`,
section "Live verification 2026-10-04".
**Severity:** high. Every `make up` breaks LDAP-backed SSO on the hub (LDAP error 49), and the
repair command fails on this hub because of a wrong Secret default.

## Root cause

1. `bin/cluster-up` reads the Keycloak LDAP bind password from `_ldap_admin_pass`, which
   `shopping_cart_seed_sandbox_vault_kv` sets from Vault `secret/ldap/admin.admin_password`.
   That is the password of the shopping-cart `ldap` Deployment.
   The Keycloak provider binds `cn=ldap-admin,dc=home,dc=org` at `openldap.identity.svc`, which is
   the `openldap-0` StatefulSet. Its password lives in Secret `identity/openldap-admin` key
   `LDAP_ADMIN_PASSWORD`, the source that `keycloak_provision_shopping_cart_realm` and step 10d.5
   (via the pod's own `$LDAP_ADMIN_PASSWORD`) already use.
2. `keycloak_provision_shopping_cart_realm` defaults its admin Secret to `keycloak-admin-secret`.
   This hub keeps the admin login in `identity/keycloak-secrets`, so the documented repair warns
   and does nothing unless the operator sets `KEYCLOAK_SMOKE_ADMIN_SECRET_NAME=keycloak-secrets`.

## Fix (Codex)

Target files: `bin/cluster-up`, `scripts/plugins/keycloak.sh`, `scripts/tests/bin/cluster_up.bats`,
`scripts/tests/plugins/keycloak.bats`. Nothing else.

### F1. New helper in `bin/cluster-up`

Insert directly **above** `function _acg_keycloak_ldap_provider_id() {`:

```bash
function _acg_ldap_bind_pass() {
  kubectl get secret openldap-admin -n identity --context k3d-k3d-cluster \
    -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' 2>/dev/null | base64 --decode 2>/dev/null || true
}

```

### F2. Realm import (Step 10d)

Old:

```bash
  else
    _realm_json=$(sed \
```

New:

```bash
  else
    _ldap_bind_pass="$(_acg_ldap_bind_pass)"
    _ldap_bind_pass_sed=$(printf '%s' "${_ldap_bind_pass}" | sed 's/[\/&]/\\&/g')
    _realm_json=$(sed \
```

Old:

```bash
      -e "s/\${LDAP_BIND_CREDENTIAL}/${_ldap_admin_pass}/g" \
```

New:

```bash
      -e "s/\${LDAP_BIND_CREDENTIAL}/${_ldap_bind_pass_sed}/g" \
```

### F3. Step 10d.6

Old:

```bash
    _ldap_component_id=$(_acg_keycloak_ldap_provider_id "${_kc_pod}" "${_kc_admin_pass}" || true)
    if [[ -n "${_ldap_component_id}" ]]; then
```

New:

```bash
    _ldap_bind_pass="$(_acg_ldap_bind_pass)"
    _ldap_component_id=$(_acg_keycloak_ldap_provider_id "${_kc_pod}" "${_kc_admin_pass}" || true)
    if [[ -z "${_ldap_bind_pass}" ]]; then
      _warn "[acg-up] LDAP bind password not readable from identity/openldap-admin — skipping bind credential reconciliation"
    elif [[ -n "${_ldap_component_id}" ]]; then
```

In the same step, replace both remaining uses of `"${_ldap_admin_pass}"`:
- `printf '%s\n%s\n' "${_kc_admin_pass}" "${_ldap_admin_pass}" | \` becomes
  `printf '%s\n%s\n' "${_kc_admin_pass}" "${_ldap_bind_pass}" | \`
- `env KC_ADMIN_PASS="${_kc_admin_pass}" LDAP_BIND="${_ldap_admin_pass}" sh -c '` becomes
  `env KC_ADMIN_PASS="${_kc_admin_pass}" LDAP_BIND="${_ldap_bind_pass}" sh -c '`

Leave the `: "${_ldap_admin_pass:=}"` default line (around line 77) in place. Do not touch
`scripts/plugins/shopping_cart.sh`.

### F4. Admin-Secret fallback in `scripts/plugins/keycloak.sh`

Add this function directly **above** `function keycloak_provision_shopping_cart_realm() {`:

```bash
function _keycloak_smoke_admin_secret_name() {
   local ns="$1" preferred="$2"
   if ! _kubectl --no-exit -n "$ns" get secret "$preferred" >/dev/null 2>&1 && \
      _kubectl --no-exit -n "$ns" get secret keycloak-secrets >/dev/null 2>&1; then
      printf '%s\n' keycloak-secrets
      return 0
   fi
   printf '%s\n' "$preferred"
}

```

In `keycloak_provision_shopping_cart_realm`:

Old:

```bash
   local admin_secret="${KEYCLOAK_SMOKE_ADMIN_SECRET_NAME:-keycloak-admin-secret}"
```

New:

```bash
   local admin_secret
   admin_secret=$(_keycloak_smoke_admin_secret_name "$ns" "${KEYCLOAK_SMOKE_ADMIN_SECRET_NAME:-keycloak-admin-secret}")
```

`local ns=...` is already declared on the line above it. Confirm this. If it is not, stop and report.

## Gates (offline; stubs only; no live cluster)

- **BATS `cluster_up.bats`, behavior:** extract `_acg_ldap_bind_pass` with
  `sed -n '/function _acg_ldap_bind_pass/,/^}/p'`. Use a `kubectl` stub that records argv and
  prints `printf 'p/w&x+y' | base64`. The helper must print `p/w&x+y`, and argv must contain
  `openldap-admin` and `LDAP_ADMIN_PASSWORD`.
- **BATS `cluster_up.bats`, source:**
  - `grep -c '_ldap_admin_pass' bin/cluster-up` is exactly `1` (only the default line).
  - The 10d.6 block (`sed -n "/Step 10d.6\/14 — Reconciling/,/step-10d6-ldap-bind\"/p"`) contains
    `_acg_ldap_bind_pass` and `not readable from identity/openldap-admin`.
  - The realm-import `sed` uses `_ldap_bind_pass_sed`.
- **BATS `keycloak.bats`, behavior:** source `scripts/plugins/keycloak.sh` the same way the
  existing tests in that file do. Stub `_kubectl` so that `get secret keycloak-admin-secret` fails and
  `get secret keycloak-secrets` succeeds. `_keycloak_smoke_admin_secret_name identity keycloak-admin-secret`
  must print `keycloak-secrets`. When both Secrets exist it prints `keycloak-admin-secret`.
  When neither exists it prints `keycloak-admin-secret`.
- **Mutation:** in the `_acg_ldap_bind_pass` helper, change `openldap-admin` to `ldap-secrets`
  (snapshot with `cp`, then restore and `cmp`; never `git checkout`). The behavior test must go red.
- `shellcheck bin/cluster-up scripts/plugins/keycloak.sh` adds no new warnings compared with HEAD.
  `bats scripts/tests/bin/cluster_up.bats scripts/tests/plugins/keycloak.bats` is all green.
- `git diff --stat` shows only the four target files.

## Definition of Done

- [ ] F1–F4 applied exactly as written.
- [ ] Gates above pass; paste the BATS summary, the shellcheck comparison and the mutation result.
- [ ] Commit message, verbatim:
      `fix(cluster-up): bind Keycloak LDAP with the openldap-admin password and fall back to keycloak-secrets for the admin login`
- [ ] Report the SHA. If `.git/index.lock` is denied, stop after the edits and the gates, and report that.

## What NOT to Do

- Do NOT create a PR. Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the four targets. Do NOT commit to `main`.
- Do NOT read any Secret value or run anything against a live cluster.

## Live verification (Claude, next sandbox `make up`)

- 10d.6 prints `LDAP federation bind credential reconciled and full sync triggered`, and 10d.7 prints
  `LDAP group sync complete`.
- The read-only `testLDAPConnection action=testAuthentication` exits 0 after the run.
- The Keycloak log has no `error code 49` after the run.
