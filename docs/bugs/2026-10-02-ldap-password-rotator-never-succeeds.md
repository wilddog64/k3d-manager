# `ldap-password-rotator` has never succeeded on the hub: `openssl` missing, and a hardcoded `vault.vault.svc`

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** medium. Monthly LDAP password rotation has not run since the hub rebuild (CronJob created
2026-09-20, `lastSuccessfulTime` empty). `KubeJobFailed` for `identity/ldap-password-rotator-29846880` has been
firing since 2026-10-01T00:06Z.
**Status:** OPEN
**Related:** `docs/bugs/v1.23.0-bugfix-grafana-rotator-openssl-not-found.md`: the same `openssl: not found` on
`alpine/k8s`, fixed there for the Grafana rotator only. This is the LDAP rotator's copy of that defect.

## Evidence (hub `k3d-k3d-cluster`, 2026-10-02; read-only)

- Job `ldap-password-rotator-29846880`: `Failed=True BackoffLimitExceeded`. Its pods are gone, so there are no logs.
- The other three monthly rotators (`argocd-`, `grafana-`, `keycloak-credential-rotator`) succeeded on 2026-10-01.
  They use the same image and the same create-only `pods/exec` RBAC, so RBAC is not the cause.
- The image `docker.io/alpine/k8s:1.31.4` (`LDAP_ROTATOR_IMAGE`, `scripts/etc/ldap/vars.sh:99`) has **no
  `openssl`**; it has `sha256sum`, `xargs`, `base64`, `od`, `head`, `tr`, `kubectl` and `curl`.
- **No password was changed.** `chengkai.liang` and `test-user` both have `modifyTimestamp: 20260920234852Z`.
  The admin bind the script uses (`cn=ldap-admin,dc=home,dc=org` on `:1389`) works, and both user DNs exist.
- The live CronJob has `VAULT_NAMESPACE=secrets` and `VAULT_ADDR=http://vault.vault.svc:8200`. There is no `vault`
  namespace on the hub; the Vault service is `vault.secrets.svc`.

## Cause

1. `generate_password` in `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl` runs
   `openssl rand -base64 18 | tr -d '/+=' | head -c 20`. Under `sh` there is no `pipefail`, so the missing
   `openssl` yields an **empty** password with exit 0. The script then calls `ldappasswd -s ""`, which fails, so each
   user counts as a failure and the script exits 1.
2. Behind that: `_ldap_deploy_password_rotator` (`scripts/plugins/ldap.sh:937-938`) forces
   `VAULT_ADDR="http://vault.vault.svc:8200"` regardless of `vault_ns`. `update_vault_password` runs inside `vault-0`
   with that address, so the Vault write would fail **after** the LDAP password had already changed. That would leave
   the user with a password nobody holds. Fixing (1) alone would turn this silent failure into a lockout.

## Fix

1. **Template** (`scripts/etc/ldap/ldap-password-rotator.yaml.tmpl`, the `rotate.sh` script):
   - `generate_password`: replace the `openssl` line with the portable form already used by the Grafana rotator,
     `head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'` (48 hex characters).
   - In the per-user loop, right after `new_password=$(generate_password)`: if `[ -z "$new_password" ]`, call
     `error "  ✗ Empty generated password for $user"`, increment the failure count, and `continue`. Never call
     `ldappasswd` with an empty `-s`.
   - **Vault preflight**, in `main` after `vault_token=...` and before the loop:
     `kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- vault status -address="$VAULT_ADDR" >/dev/null 2>&1`.
     Use the `-address` flag, not an `env VAR=` prefix: the pre-commit `_agent_audit` rejects `env VAR=` inside a
     `kubectl exec` line.
     On failure, `error "Vault not reachable at $VAULT_ADDR from vault-0; aborting before any LDAP change"` and
     `exit 1`. `vault status` needs no token; do not add the token to this command.
   - Change nothing else in the script: not the LDAP/Vault write commands, the Slack notice or the RBAC.
2. **Deploy** (`scripts/plugins/ldap.sh`, `_ldap_deploy_password_rotator`): replace the hardcoded address with
   `export VAULT_ADDR="http://vault.${vault_ns}.svc:8200"`. Keep the comment above it.

Out of scope, already in the backlog ("ldap rotator stdin"): the admin password, Vault token and new password are
passed in `kubectl exec` argv.

## Tests (new `scripts/tests/plugins/ldap_password_rotator.bats`; no cluster)

1. Render the template with `envsubst` using the variable list from `_ldap_deploy_password_rotator`, extract
   `data["rotate.sh"]` with `yq`, and assert it contains no `openssl` and does contain `/dev/urandom`.
2. Extract the `generate_password` function from the rendered script, run it under `/bin/sh` with a `PATH` that has
   no `openssl`, and assert a 48-character `[0-9a-f]` result.
3. The empty-password guard: assert the loop checks `-z "$new_password"` **before** the `update_ldap_password` call
   (compare line numbers in the rendered script).
4. The Vault preflight appears in `main` before the `while` loop and contains `vault status -address=` and no `VAULT_TOKEN`.
5. `_ldap_deploy_password_rotator` with `VAULT_NS=secrets` exports `VAULT_ADDR=http://vault.secrets.svc:8200`.
   Stub `_kubectl`, `envsubst` and `_info`, and capture the exported value. No `vault.vault.svc` literal remains in
   `scripts/plugins/ldap.sh`.

Mutations, each red, then `cp`-restored and `cmp`-proved: (a) put the `openssl` line back → tests 1–2 red;
(b) hardcode `vault.vault.svc` again → test 5 red; (c) drop the empty guard → test 3 red.

## Rules

- `bats scripts/tests/plugins/ldap_password_rotator.bats` and `bats scripts/tests/plugins/` are green; `shellcheck`
  is clean on `scripts/plugins/ldap.sh`.
- No cluster, network or git commits. Leave the changes uncommitted. Do not touch `CHANGELOG.md` or memory-bank.
- Update this doc: Status FIXED (pending rollout), plus a short Resolution section.

## Rollout (operator)

1. Re-apply the rotator: `deploy_ldap` calls `_ldap_deploy_password_rotator` when `LDAP_ROTATOR_ENABLED=1`.
2. `kubectl --context k3d-k3d-cluster -n identity delete job ldap-password-rotator-29846880`; this clears
   `KubeJobFailed`.
3. Optional, the operator's call: run it once with
   `kubectl -n identity create job --from=cronjob/ldap-password-rotator ldap-rotator-manual`. This **really
   rotates** the LDAP passwords of `chengkai.liang` and `test-user` and writes them to Vault `secret/ldap/users/*`.
   Otherwise the next scheduled run is 2026-11-01.
