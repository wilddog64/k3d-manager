# Bug: cluster-up Step 10d.5 fails — the hub LDAP rejects the `openldap-admin` Secret's password

**Status:** FIXED (`244701bf`) — live proof pending (hub rebuild drill 2026-10-29)
**Priority:** P2 — degraded with a workaround (restart `statefulset/openldap`, rerun `make up`); downgraded from P1 2026-10-17 by the operator
**Filed:** 2026-10-16
**Detected by:** live run (operator's `make up` before `make e2e-sandbox`, diagnosed by Claude, read-only)
**Affected:** `bin/cluster-up` Step 10d.5 (`Seeding Keycloak LDAP user passwords`), hub `identity/openldap-0`
**Branch:** `k3d-manager-v1.43.4` (proposed)
**Approval:** explicit 2026-10-17 "go ahead to dispatch to codex and downgrade P1 to P2" (operator)
**Related:** `docs/issues/2026-05-12-live-ldap-bind-secret-invalid-credentials.md` (same symptom, May),
`docs/bugs/2026-10-02-ldap-password-rotator-never-succeeds.md` (rotates users only, not the admin)

## Observed failure

```text
INFO: [acg-up] Step 10d.5/14 — Seeding Keycloak LDAP user passwords in LDAP + Vault...
WARN: [acg-up] Failed to set LDAP password for user 'admin'
WARN: [acg-up] Failed to set LDAP password for user 'developer'
WARN: [acg-up] Failed to set LDAP password for user 'operator'
ERROR: [acg-up] LDAP password seed failed verification; checkpoint not written
make: *** [up] Error 1
```

Seen at 13:06Z and ~16:46Z on 2026-10-16. `make up` exits at 10d.5, so Steps 10e–14 never run on
these runs (Keycloak/frontend/Grafana listeners, Cloudflare tunnel, ClusterSecretStore check, TTL
watcher, ACG observability).

## Evidence (hub `k3d-k3d-cluster`, read-only, 2026-10-16)

- `openldap-0` is Running, started 02:22:33Z. Its PVC `data-openldap-0` was created 02:22:28Z, so
  the directory was initialised fresh at that time.
- The pod's env comes from `envFrom: secretRef openldap-admin`. That Secret is owned by
  ExternalSecret `openldap-admin` (SecretSynced, refresh 1h), created 02:06:23Z, `resourceVersion`
  10643 (never updated since).
- Inside the pod, `ldapwhoami -x -H ldap://localhost:1389 -D cn=ldap-admin,dc=home,dc=org -w
  "$LDAP_ADMIN_PASSWORD"` returns **`Invalid credentials (49)`**. The slapd log has 7 `err=49`
  results, all on the seed's admin binds plus this check.
- Keycloak (`10.42.1.27`) binds as the same `cn=ldap-admin` DN successfully (`err=0`) every few
  seconds, using its own copy of the credential.
- No `PASSMOD` or `MOD dn="cn=ldap-admin"` appears in the slapd log since start.
- `ldappasswd`, `ldapwhoami`, `mktemp` exist in the image. The seed fails at the admin bind, not on
  a missing tool or TTY.

## Cause (found 2026-10-16, Claude, read-only; no value printed)

The pod's environment is stale; the directory and the Secret are right.

| Check (23:5xZ) | Result |
|---|---|
| bind with pod env `$LDAP_ADMIN_PASSWORD` | rc **49** |
| bind with the current `openldap-admin` Secret value (stdin) | rc **0** |
| Secret value == pod env | **no** |
| Vault `secret/ldap/openldap-admin` versions | **1 only**, created 2026-10-03T15:55Z |
| Secret writers (`managedFields`) | ESO only: created 02:06:23Z, last update **03:06:20Z** |
| `data-vault-0` / `data-openldap-0` PVCs, `vault-0` / `openldap-0` start | 02:22:19Z / 02:22:28Z, 02:22:33Z |
| container env sources | `envFrom` `openldap-env` (ConfigMap, no password keys) + Secret `openldap-admin` only |

Sequence:

1. 02:06Z: the rebuilt hub's first Vault held a freshly generated admin password, and ESO created
   the Secret from it.
2. 02:22Z: the hub-data restore replaced `data-vault-0` and `data-openldap-0` with the snapshot. The
   restored directory and the restored Vault both carry the 2026-10-03 password. `openldap-0` started
   from the Secret as it was, with the pre-restore password in its environment.
3. 03:06Z: ESO's hourly refresh brought the Secret in line with the restored Vault. Keycloak binds
   with the restored value (`err=0`). `openldap-0` was never restarted, so its environment still holds
   the pre-restore password.
4. Step 10d.5 binds with `-w "$LDAP_ADMIN_PASSWORD"` from that environment, which fails with 49 on
   every run until the pod restarts.

Code gap: `_hub_data_refresh_dependents` (`scripts/plugins/hub_data.sh:789`) force-syncs every
ExternalSecret and then restarts `deployment/keycloak`, the Grafana deployment and
`deployment/argocd-server`, but **not `statefulset/openldap`**, which reads the same Vault data
through `envFrom`. `hub_data_verify_ldap` checks entry count and DN digest, not an admin bind, so
the restore reports success. (The 2026-05-12 issue has the same symptom and probably the same
class of cause.)

Fix shape (to spec):
- (a) Add `statefulset/openldap` to `_hub_data_refresh_dependents`: `rollout restart`, then
  `rollout status` after the ExternalSecret wait.
- (b) Make Step 10d.5 bind with the Secret's current value passed on stdin, not the pod
  environment, so a stale environment cannot block it.
- (c) Add an admin-bind check (rc only) to `hub_data_verify_ldap`.

The earlier candidates (chart init source, a `cn=config` rewrite, two Vault paths) are ruled out.

### Earlier hypotheses (superseded)

The directory's admin password is not the value in the pod env, though the PVC was initialised
fresh from a Secret that has not changed since. Keycloak holds the working value. Candidates to
check, in order (all need the operator, because they compare credential values):

1. The chart initialises the root password from a source other than `LDAP_ADMIN_PASSWORD` env (a
   chart value or the `init-schema` / `init-tls-secret` init containers).
2. Something rewrote the admin password between 02:22Z and 13:06Z through `cn=config`
   (`olcRootPW`), which the stats log level would not show.
3. Vault holds two different admin passwords: the `openldap-admin` ExternalSecret path and the path
   Keycloak's LDAP bind credential comes from.

Compare by hash, never by printing: `sha256sum` of each value, from the operator's shell.

## Expected

The `openldap-admin` Secret's password binds as `cn=ldap-admin,dc=home,dc=org`, and Step 10d.5
seeds and verifies the three users.

## Workaround

Operator only (cluster-mutating): `kubectl --context k3d-k3d-cluster -n identity rollout restart
statefulset/openldap` and `rollout status`, then rerun `make up`. The 10d.5 checkpoint was not
written, so the run resumes there. The PVC is kept, so no data changes; Keycloak's LDAP federation
blips for the restart.

## Fix (spec for Codex)

**Branch:** `k3d-manager-v1.43.4` (already checked out; do not create another).

### F1 — the recovery restarts OpenLDAP after ESO has refreshed its Secret

`scripts/plugins/hub_data.sh`, `_hub_data_refresh_dependents`. A restore swaps the OpenLDAP data under
a running pod whose `envFrom` copy of `openldap-admin` is now stale. Restart it after the
ExternalSecret wait (already earlier in the function), and wait for it, because step 8's verification
reads LDAP next.

Old:
```bash
  _kubectl --context "$context" -n cicd rollout restart deployment/argocd-server || _warn "[hub-recover] could not restart argocd-server; SSO may use a stale client secret until it restarts"
}
```

New:
```bash
  _kubectl --context "$context" -n cicd rollout restart deployment/argocd-server || _warn "[hub-recover] could not restart argocd-server; SSO may use a stale client secret until it restarts"
  _kubectl --context "$context" -n identity rollout restart statefulset/openldap || return 1
  _kubectl --context "$context" -n identity rollout status statefulset/openldap --timeout=300s || return 1
}
```

### F2 — Step 10d.5 binds with the Secret's current password, from a file, not the pod env

`bin/cluster-up`, Step 10d.5. The pod's `$LDAP_ADMIN_PASSWORD` can be stale (F1's cause). Read the
`openldap-admin` Secret once with the existing `_acg_ldap_bind_pass`, send it on stdin ahead of the two
user-password lines, and pass it to `ldappasswd` with `-y` so it is never on argv in the pod.

Old:
```bash
  else
    _ldap_seed_failed=0
    for _ldap_user in admin developer operator; do
```

New:
```bash
  else
    _ldap_admin_pass="$(_acg_ldap_bind_pass)"
    if [[ -z "${_ldap_admin_pass}" ]]; then
      _err "[acg-up] LDAP admin password not readable from identity/openldap-admin — cannot seed user passwords"
      exit 1
    fi
    _ldap_seed_failed=0
    for _ldap_user in admin developer operator; do
```

Old:
```bash
      if printf '%s\n%s\n' "${_ldap_user_pass}" "${_ldap_user_pass}" | \
          kubectl exec -i -n identity --context k3d-k3d-cluster "${_ldap_pod}" -- \
            sh -ceu '
              ldappasswd -x -H ldap://localhost:1389 \
                -D "cn=ldap-admin,dc=home,dc=org" \
                -w "$LDAP_ADMIN_PASSWORD" \
                -S "uid=$1,ou=users,dc=home,dc=org"
            ' sh "${_ldap_user}" >/dev/null 2>&1; then
```

New:
```bash
      if printf '%s\n%s\n%s\n' "${_ldap_admin_pass}" "${_ldap_user_pass}" "${_ldap_user_pass}" | \
          kubectl exec -i -n identity --context k3d-k3d-cluster "${_ldap_pod}" -- \
            sh -ceu '
              _ldap_admin_password_file=$(mktemp)
              trap "rm -f \"${_ldap_admin_password_file}\"" EXIT
              IFS= read -r _ldap_admin_password
              printf "%s" "${_ldap_admin_password}" > "${_ldap_admin_password_file}"
              ldappasswd -x -H ldap://localhost:1389 \
                -D "cn=ldap-admin,dc=home,dc=org" \
                -y "${_ldap_admin_password_file}" \
                -S "uid=$1,ou=users,dc=home,dc=org"
            ' sh "${_ldap_user}" >/dev/null 2>&1; then
```

`read` consumes only the first line; `ldappasswd -S` reads the remaining two as before.

### F3 — the restore's LDAP verification proves the admin bind, not just the entries

`scripts/plugins/hub_data.sh`. Entry count and DN digest both pass while the admin bind fails, which is
how this shipped. Add a helper next to `_hub_data_ldap_dn_digest` (it prints nothing; rc only) and call
it from `hub_data_verify_ldap`. It runs after F1's restart (recover step 7 → step 8), so the pod env
equals the Secret.

Add after the `_hub_data_ldap_dn_digest` function:
```bash
function _hub_data_ldap_admin_bind() {
  "$@" -n identity exec statefulset/openldap -- sh -c 'f=$(mktemp); trap "rm -f \"$f\"" EXIT; printf "%s" "$LDAP_ADMIN_PASSWORD" > "$f"; ldapwhoami -x -H ldap://localhost:1389 -D "cn=ldap-admin,dc=home,dc=org" -y "$f"' >/dev/null 2>&1
}
```

In `hub_data_verify_ldap`, old:
```bash
  want="$(jq -r '.ldap_entry_count' "$inventory")"; actual="$(_hub_data_ldap_entry_count _kubectl --context "$context")"; [[ "$actual" == "$want" ]] || return 1
```

New:
```bash
  want="$(jq -r '.ldap_entry_count' "$inventory")"; actual="$(_hub_data_ldap_entry_count _kubectl --context "$context")"; [[ "$actual" == "$want" ]] || return 1
  _hub_data_ldap_admin_bind _kubectl --context "$context" || { _err '[hub-data] LDAP admin bind failed with the openldap-admin password'; return 1; }
```

### F4 — tests

`scripts/tests/plugins/hub_data.bats`:

- **"recover D2: refresh force-syncs, waits, discovers Keycloak, then restarts dependents"** — append
  `[[ "${calls[6]}" == *"rollout restart statefulset/openldap"* ]]` and
  `[[ "${calls[7]}" == *"rollout status statefulset/openldap"* ]]`.
- New test **"recover D2: an OpenLDAP restart failure fails the refresh"** — stub `_kubectl` to return 0
  for `get deployment/keycloak`, 1 for any call containing `statefulset/openldap`, 0 otherwise; with
  `K3DM_HUB_DATA_KEYCLOAK_POLL_S=0`, `run _hub_data_refresh_dependents ctx`; assert `status` is 1.
- **"recover B4-R3: verification passes context to kubectl"** — add
  `_hub_data_ldap_admin_bind() { printf '%s\n' "$*" >> "$CALL_LOG"; }` next to the other stubs (without
  it the test reaches a real `kubectl`).
- New test **"recover B4-R3: a failed LDAP admin bind fails LDAP verification"** — same inventory and
  count stubs as B4-R3, `_hub_data_ldap_admin_bind() { return 1; }`; `run --separate-stderr
  hub_data_verify_ldap "$TEST_ROOT/inventory.json" target-context`; assert `status` is 1 and `stderr`
  contains `LDAP admin bind failed`.

`scripts/tests/bin/cluster_up.bats`, new test **"acg-up seeds LDAP users with the openldap-admin Secret,
not the pod env"**: extract the Step 10d.5 block the way the existing "verifies every LDAP password" test
does (`sed -n "/Step 10d.5\/14/,/Step 10d.6\/14/p" bin/cluster-up`), then assert the block contains
`_acg_ldap_bind_pass` and `-y "${_ldap_admin_password_file}"`, and does **not** contain
`LDAP_ADMIN_PASSWORD`. Use `run`/`[ "$status" ... ]` or `|| false`; never a bare `! grep` (it never fails
a BATS test).

**Mutation checks** (Claude runs these on a temporary copy afterwards; listed so the tests are written to
catch them): drop F1's restart line → D2 fails; restore `-w "$LDAP_ADMIN_PASSWORD"` → the cluster_up test
fails; drop F3's call → the new B4-R3 test fails.

## Files

- `scripts/plugins/hub_data.sh`
- `bin/cluster-up`
- `scripts/tests/plugins/hub_data.bats`
- `scripts/tests/bin/cluster_up.bats`

## Rules

- `shellcheck -S warning scripts/plugins/hub_data.sh bin/cluster-up` — no new warnings.
- `bats scripts/tests/plugins/hub_data.bats scripts/tests/bin/cluster_up.bats` — fully green.
- Paste both outputs.

## Definition of Done

- [ ] F1–F4 applied exactly; gates green (paste output).
- [ ] Commit message: `fix(ldap): refresh and bind with the current openldap-admin password after a restore`.
- [ ] Commit on `k3d-manager-v1.43.4` and report the SHA.

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT modify files outside `## Files` — including this doc and `memory-bank/`.
- Do NOT run `make up`, `bin/cluster-up`, `hub_data_recover`, or any command against a live cluster.
- Do NOT print, log or echo any password; no `-w` with a password on any `ldap*` command.

## Live proof

The hub rebuild drill on 2026-10-29 (`project_hub_rebuild_drill_2026_10_29`): recover step 8 passes with
the admin-bind check, and `make up` Step 10d.5 logs `LDAP password set and verified` for all three users.

## Landed (2026-10-17)

`244701bf` on `k3d-manager-v1.43.4`, via `bin/k3dm-codex-dispatch` (task `ldap-admin-bind-refresh`).
Codex left the change uncommitted; Claude committed it with the spec's message after checking it:

- The diff matches F1–F4 exactly and touches only the four files in `## Files`.
- `shellcheck -S warning` is clean on both scripts.
- `bats scripts/tests/plugins/hub_data.bats scripts/tests/bin/cluster_up.bats` passes 170/170.
- Mutation checks, each on a temporary copy, all caught:
  - dropping F1's restart fails D2;
  - restoring `-w "$LDAP_ADMIN_PASSWORD"` fails the new cluster_up test;
  - dropping F3's call fails the new B4-R3 test.
