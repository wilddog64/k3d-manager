# Bug: Vault ESO role rewrites drop the `cosign-verify` grant

**Branch:** `k3d-manager-v1.33.0`
**Filed:** 2026-09-13
**Status:** FIXED `b3bc737c` (Codex; Claude verified: diff = spec, shellcheck 0, BATS 101/101; Claude pushed) — live grant restore pending (operator)
**Files:** `scripts/plugins/vault.sh`, `scripts/tests/plugins/vault_role_policy_merge.bats` (new), `CHANGELOG.md`
**Related:** `docs/issues/2026-09-05-vault-kv-and-eso-policy-loss-grafana-cosign.md`, `docs/issues/2026-09-09-hub-kine-history-and-hostinger-cosign-role.md`

## Problem

On 2026-09-13 Slack alerted "ESO not sync". Two ExternalSecrets were failing, `platform-ops/cosign-public-key` on the hub and `kyverno/cosign-public-key` on hostinger, both with:

```
cannot read secret data from Vault: ... GET .../v1/secret/data/cosign/signing  Code: 403 permission denied
```

`signing.sh` `_signing_grant_eso_read` adds the `cosign-verify` policy to the ESO Vault role by *appending* it to the role's existing policies. Two other role writers then *replace* the policy list wholesale:

- `configure_vault_app_auth` writes `auth/<mount>/role/eso-app-cluster` with `policies=app-cluster-reader`.
- `_vault_configure_secret_reader_role` writes `auth/kubernetes/role/<role>` with `policies="eso-apps,<policy>"`. It runs from `ldap.sh`, `jenkins.sh`, and `hub_recovery.sh` `_hub_recovery_ensure_eso_apps_role`.

Any rebuild, recovery, or re-run of these writers silently removes `cosign-verify`. ESO keeps using its cached Vault token until it next logs in (here, the OrbStack restart), so the failure shows up far from its cause. This is the third occurrence: 2026-09-05, 2026-09-09, and now.

## Fix

The role writers keep setting the policies they own, and also preserve any other non-`default` policies already on the role. A new helper reads the existing role and merges.

### S1 — `scripts/plugins/vault.sh`: new helper

Insert immediately **before** `function _vault_configure_secret_reader_role() {`:

```bash
function _vault_role_merged_policies() {
  local ns="$1" release="$2" role_path="$3" desired="$4"
  local role_json="" existing=""
  role_json=$(_vault_exec --no-exit "$ns" "vault read -format=json ${role_path}" "$release" 2>/dev/null || true)
  existing=$(printf '%s' "$role_json" | jq -r '(.data.token_policies // [])[]' 2>/dev/null || true)
  printf '%s\n%s\n' "${desired//,/$'\n'}" "$existing" \
    | awk '/^[A-Za-z0-9._-]+$/ && $0 != "default" && !seen[$0]++' \
    | paste -sd, -
}
```

Desired policies come first in their given order. Existing extras are appended in role order. Duplicates, `default`, and any name with characters outside `[A-Za-z0-9._-]` are dropped. If the role is missing or unreadable, the result is just the desired list.

### S2 — `configure_vault_app_auth`

Old:

```bash
  printf -v safe_audience '%q' "$audience"
  _vault_exec "$ns" "vault write ${safe_mount_role} \
    bound_service_account_names=${safe_eso_sa} \
    bound_service_account_namespaces=${safe_eso_ns} \
    audience=${safe_audience} \
    policies=app-cluster-reader \
    ttl=1h" "$release"
```

New:

```bash
  printf -v safe_audience '%q' "$audience"
  local safe_policies
  safe_policies=$(_vault_role_merged_policies "$ns" "$release" "auth/${mount}/role/${role}" "app-cluster-reader")
  _vault_exec "$ns" "vault write ${safe_mount_role} \
    bound_service_account_names=${safe_eso_sa} \
    bound_service_account_namespaces=${safe_eso_ns} \
    audience=${safe_audience} \
    policies=${safe_policies} \
    ttl=1h" "$release"
```

### S3 — `_vault_configure_secret_reader_role`

Old:

```bash
  if [[ "$role" == "eso-ldap-directory" && -n "$apps_policy" ]]; then
     role_policies="${apps_policy},${policy}"
  fi
  printf -v role_cmd
```

New:

```bash
  if [[ "$role" == "eso-ldap-directory" && -n "$apps_policy" ]]; then
     role_policies="${apps_policy},${policy}"
  fi
  role_policies=$(_vault_role_merged_policies "$ns" "$release" "auth/kubernetes/role/${role}" "$role_policies")
  printf -v role_cmd
```

The old block ends with the start of the existing `printf -v role_cmd ...` line. Leave that line unchanged.

Change nothing else in `vault.sh`.

## Tests — `scripts/tests/plugins/vault_role_policy_merge.bats` (new)

Model the harness on `scripts/tests/plugins/vault_app_auth_enable_idempotent.bats`:
- Set `REPO_ROOT`, `SCRIPT_DIR`, and a `PLUGINS_DIR` holding a dummy `eso.sh`.
- Stub `_err`/`_warn`/`_info`, then source `scripts/plugins/vault.sh`.
- Afterwards stub `_vault_login`, `_kubectl`, `_vault_policy_exists` (returns 0), `_vault_exec_stream` (drains stdin, returns 0), and `_no_trace() { "$@"; }`.
- `_vault_exec` logs `$*` to `${BATS_TEST_TMPDIR}/vault.log`. When its arguments contain `vault read -format=json`, it prints `$ROLE_JSON` (a per-test variable, default empty). Otherwise it prints nothing and returns 0.

Tests:

1. `_vault_role_merged_policies: desired first, existing extras appended, default and duplicates dropped`
   - `ROLE_JSON='{"data":{"token_policies":["default","eso-apps","cosign-verify","bad name"]}}'`
   - `run _vault_role_merged_policies secrets vault auth/kubernetes/role/r "eso-apps,eso-ldap-directory"`
   - Output equals `eso-apps,eso-ldap-directory,cosign-verify`.
2. `_vault_role_merged_policies: unreadable role yields desired only`
   - `ROLE_JSON='Error reading'`; desired `app-cluster-reader` → output `app-cluster-reader`.
3. `configure_vault_app_auth preserves an existing cosign-verify grant`
   - `ROLE_JSON='{"data":{"token_policies":["app-cluster-reader","cosign-verify"]}}'`, with `APP_CLUSTER_API_URL` and `APP_CLUSTER_CA_CERT_PATH` set as in the idempotent test.
   - Status 0.
   - The log has a read of `auth/kubernetes-app/role/eso-app-cluster`.
   - The log line containing `role/eso-app-cluster` and `policies=` contains `policies=app-cluster-reader,cosign-verify`.
4. `_vault_configure_secret_reader_role preserves an existing cosign-verify grant`
   - `ROLE_JSON='{"data":{"token_policies":["default","eso-apps","eso-ldap-directory","cosign-verify"]}}'`
   - `run _vault_configure_secret_reader_role secrets vault eso-ldap-sa identity secret ldap eso-ldap-directory`
   - Status 0.
   - The role write line contains `policies="eso-apps,eso-ldap-directory,cosign-verify"`.

Assert on meaningful tokens; never `grep -F` a whole source line.

Also run the existing suites `vault_app_auth.bats`, `vault_app_auth_enable_idempotent.bats`, `vault.bats`, `signing.bats`, and `hub_recovery.bats`; all must still pass.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, add as the first bullet:

```
- Vault ESO role writers (`configure_vault_app_auth`, `_vault_configure_secret_reader_role`) now merge their policies with those already on the role instead of replacing them, so a rebuild or hub recovery no longer silently strips the `cosign-verify` grant and breaks the `cosign-public-key` ExternalSecret with a Vault 403
```

## Definition of Done

- [ ] S1–S3 applied exactly; no other lines in `scripts/plugins/vault.sh` changed.
- [ ] `shellcheck -x scripts/plugins/vault.sh`: no new warnings versus the pre-change file (paste both counts).
- [ ] `bats scripts/tests/plugins/vault_role_policy_merge.bats`: 4/4 pass (paste summary).
- [ ] `bats` on `vault_app_auth.bats`, `vault_app_auth_enable_idempotent.bats`, `vault.bats`, `signing.bats`, `hub_recovery.bats`: all pass (paste summaries).
- [ ] CHANGELOG bullet added.
- [ ] Commit message, verbatim: `fix(vault): merge ESO role policies instead of replacing them so cosign-verify survives rebuilds`
- [ ] Pushed; `git rev-parse origin/k3d-manager-v1.33.0` equals the commit SHA.

## Live restore (operator — NOT for Codex)

The fix prevents the next loss; it does not restore today's lost grants. After the commit, the user runs `signing_restore` against the hub, then against hostinger with `SIGNING_ESO_ROLE=eso-app-cluster SIGNING_ESO_AUTH_MOUNT=kubernetes-ubuntu-hostinger`. Claude confirms the exact invocation before the user runs it. Verify that `cosign-public-key` shows `SecretSynced True` on both clusters.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT run `kubectl`, `vault`, `signing_restore`, or any `k3d-manager` command against a live cluster. Tests use stubs only.
- Do NOT modify files outside the three listed targets. Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, `scripts/plugins/signing.sh`, or memory-bank.
- Do NOT remove or reorder the policies each writer already sets.
- Do NOT use `grep -F` on source lines in BATS.
