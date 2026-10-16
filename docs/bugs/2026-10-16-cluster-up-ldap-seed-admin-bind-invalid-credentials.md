# Bug: cluster-up Step 10d.5 fails — the hub LDAP rejects the `openldap-admin` Secret's password

**Status:** OPEN — reproduced 2026-10-16 (two `make up` runs); root cause of the drift not yet found
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

## Cause (open)

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

None found yet. A rerun hits the same failure.
