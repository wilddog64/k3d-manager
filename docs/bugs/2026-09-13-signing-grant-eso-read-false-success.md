# Bug: `_signing_grant_eso_read` logs "granted" when the Vault role read/write failed

**Branch:** `k3d-manager-v1.33.0`
**Filed:** 2026-09-13
**Status:** OPEN — assigned to Codex
**Files:** `scripts/plugins/signing.sh`, `scripts/tests/plugins/signing.bats`, `CHANGELOG.md`
**Related:** `docs/bugs/2026-09-13-vault-eso-role-rewrite-drops-cosign-verify.md`, `docs/issues/2026-09-09-hub-kine-history-and-hostinger-cosign-role.md`

## Problem

On 2026-09-13 the operator ran the hostinger grant restore against the wrong kube context, so it hit the hub's Vault:
`SIGNING_ESO_ROLE=eso-app-cluster SIGNING_ESO_AUTH_MOUNT=kubernetes-ubuntu-hostinger ./scripts/k3d-manager signing_restore secrets vault`

The hub Vault has no `kubernetes-ubuntu-hostinger` mount. Output:

```
jq: parse error: Invalid numeric literal at line 1, column 6   (x3)
Error writing data to auth/kubernetes-ubuntu-hostinger/role/eso-app-cluster: ... Code: 404 ... no handler for route
INFO: [signing] granted cosign-verify read to ESO role eso-app-cluster
```

`_signing_grant_eso_read` has three defects:

1. `vault read` failed and printed error text on stdout. `role_json` was non-empty, so the `-z` guard passed. `jq` then failed on non-JSON three times, and the script kept going with empty `policies`/`bound_*`.
2. With empty values, the write would have sent `policies=,cosign-verify` and empty bound SA names/namespaces. On a real role, that replaces its policies and strips its SA bindings.
3. The `vault write` exit status is ignored, so `granted …` is logged even though the write returned 404. The function returns 0, and `signing_restore` reports success.

## Fix

### S1 — `scripts/plugins/signing.sh`: validate the role read, check the write

In `_signing_grant_eso_read`, old:

```bash
  if [[ -z "${role_json}" ]]; then
    _warn "[signing] could not read Vault role ${role}; skipping ESO read grant"
    return 0
  fi
  policies=$(printf '%s' "${role_json}" | jq -r '.data.token_policies // [] | join(",")')
```

New:

```bash
  if [[ -z "${role_json}" ]] || ! printf '%s' "${role_json}" | jq -e '.data | type == "object"' >/dev/null 2>&1; then
    _warn "[signing] could not read Vault role auth/${auth_mount}/role/${role} (wrong kube context or SIGNING_ESO_AUTH_MOUNT?); ESO read grant NOT applied"
    return 1
  fi
  policies=$(printf '%s' "${role_json}" | jq -r '.data.token_policies // [] | join(",")')
```

Old:

```bash
  _vault_exec_stream --no-exit "${vault_ns}" "${vault_release}" -- \
    vault write "auth/${auth_mount}/role/${role}" \
      bound_service_account_names="${bound_names}" \
      bound_service_account_namespaces="${bound_ns}" \
      policies="${policies},${SIGNING_VAULT_POLICY}" \
      ttl=1h
  _info "[signing] granted ${SIGNING_VAULT_POLICY} read to ESO role ${role}"
}
```

New:

```bash
  if ! _vault_exec_stream --no-exit "${vault_ns}" "${vault_release}" -- \
    vault write "auth/${auth_mount}/role/${role}" \
      bound_service_account_names="${bound_names}" \
      bound_service_account_namespaces="${bound_ns}" \
      policies="${policies:+${policies},}${SIGNING_VAULT_POLICY}" \
      ttl=1h; then
    _warn "[signing] failed to write Vault role auth/${auth_mount}/role/${role}; ESO read grant NOT applied"
    return 1
  fi
  _info "[signing] granted ${SIGNING_VAULT_POLICY} read to ESO role ${role}"
}
```

Leave the unresolved-role path unchanged (`_warn` + `return 0`), along with the "already grants" path and the role-resolution logic.

### S2 — `scripts/plugins/signing.sh`: callers surface the failure

`signing_init`, `signing_rotate_key`, and `signing_restore` each end with the same three lines. Old, in all three functions:

```bash
  _signing_apply_vault_policy "${vault_ns}" "${vault_release}"
  _signing_grant_eso_read "${vault_ns}" "${vault_release}"
  _signing_apply_pub_externalsecret
```

In `signing_init` and `signing_restore`, the new ending is:

```bash
  _signing_apply_vault_policy "${vault_ns}" "${vault_release}"
  local grant_rc=0
  _signing_grant_eso_read "${vault_ns}" "${vault_release}" || grant_rc=$?
  _signing_apply_pub_externalsecret
  return "${grant_rc}"
```

In `signing_rotate_key`, apply the same change to those three lines. Keep its trailing `_warn "[signing] key rotated; …"` line after `_signing_apply_pub_externalsecret`, and put `return "${grant_rc}"` after that `_warn` line.

Change nothing else in `signing.sh`.

## Tests — `scripts/tests/plugins/signing.bats`

Add these tests immediately after the existing `@test "_signing_grant_eso_read honors the configured ESO auth mount"`. Use the same stub style as that test: `_vault_exec` and `_vault_exec_stream` defined inside the test, with calls logged to `$BATS_TEST_TMPDIR/calls`.

1. `_signing_grant_eso_read fails without writing when the role read is not JSON`
   - `SIGNING_ESO_ROLE=eso-app-cluster`.
   - `_vault_exec` prints `No value found at auth/kubernetes-ubuntu-hostinger/role/eso-app-cluster`.
   - `_vault_exec_stream` logs `write` to calls.
   - `run _signing_grant_eso_read`, then assert:
     - status is not 0;
     - output contains `NOT applied`;
     - output does not contain `granted`;
     - output does not contain `parse error`;
     - calls has no line containing `write`.
2. `_signing_grant_eso_read fails and does not log granted when the role write fails`
   - `_vault_exec` prints valid role JSON (same as the existing test).
   - `_vault_exec_stream` returns 2.
   - `run _signing_grant_eso_read`, then assert:
     - status is not 0;
     - output contains `NOT applied`;
     - output does not contain `granted cosign-verify`.
3. `_signing_grant_eso_read appends the policy without a leading comma on an empty policy list`
   - `_vault_exec` prints `{"data":{"token_policies":[],"bound_service_account_names":["external-secrets"],"bound_service_account_namespaces":["secrets"]}}`.
   - `_vault_exec_stream` logs `$*`.
   - Status is 0.
   - Calls contains `policies=cosign-verify`, and no line contains `policies=,`.
4. `signing_restore returns non-zero when the ESO grant fails but still applies the ExternalSecret`
   - Stub `_vault_login` and `_signing_apply_vault_policy` as no-ops, and `_signing_vault_key_exists` to return 0.
   - `_signing_grant_eso_read` returns 1.
   - `_signing_apply_pub_externalsecret` logs `es` to calls.
   - Status is not 0, and calls contains `es`.

Assert on tokens. Never `grep -F` a whole source line.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, add as the first bullet:

```
- `_signing_grant_eso_read` no longer logs "granted cosign-verify read" when the Vault role read returns non-JSON (wrong kube context / missing auth mount) or the role write fails; it now warns "ESO read grant NOT applied", skips the write on an unreadable role (which would have wiped the role's policies and SA bindings), and `signing_init` / `signing_rotate_key` / `signing_restore` return non-zero
```

## Definition of Done

- [ ] S1 and S2 applied exactly; no other lines in `scripts/plugins/signing.sh` changed.
- [ ] `shellcheck -x scripts/plugins/signing.sh`: no new warnings compared with the pre-change file (paste both counts).
- [ ] `bats scripts/tests/plugins/signing.bats` — all pass, including the 4 new tests (paste the summary).
- [ ] `bats scripts/tests/plugins/vault_role_policy_merge.bats`: all pass (paste the summary).
- [ ] CHANGELOG bullet added.
- [ ] Commit message, verbatim: `fix(signing): stop reporting ESO read grant success when the Vault role read or write failed`
- [ ] Pushed, and `git rev-parse origin/k3d-manager-v1.33.0` equals the commit SHA.

## Live verification (operator — NOT for Codex)

The user runs the hostinger restore with context `ubuntu-hostinger`. It should log `granted` or `already grants`. With the hub context and the hostinger mount, it should now print `NOT applied` and exit non-zero.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT run `kubectl`, `vault`, `security`, `signing_*`, or any `k3d-manager` command against a live system. Use stubs only.
- Do NOT modify files outside the three listed targets. Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, `scripts/plugins/vault.sh`, or memory-bank.
- Do NOT change role resolution. Do NOT auto-resolve the auth mount from the ClusterSecretStore; that is out of scope.
- Do NOT use `grep -F` on source lines in BATS.
