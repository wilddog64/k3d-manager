# Bug: cluster-up Step 10d.5 fails — the hub LDAP rejects the `openldap-admin` Secret's password

**Status:** OPEN — root cause found 2026-10-16 (third repro, 23:4xZ); fix not yet specified
**Priority:** P1
**Filed:** 2026-10-16
**Detected by:** live run (operator's `make up` before `make e2e-sandbox`, diagnosed by Claude, read-only)
**Affected:** `bin/cluster-up` Step 10d.5 (`Seeding Keycloak LDAP user passwords`), hub `identity/openldap-0`
**Branch:** `k3d-manager-v1.43.4` (proposed)
**Approval:** pending
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
