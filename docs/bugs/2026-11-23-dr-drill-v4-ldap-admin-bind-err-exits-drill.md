# Bug: dr-drill dies silently at V4 — restored LDAP rejects the admin password and `_err` exits the drill

**Status:** OPEN
**Priority:** P2 (proposed) — the DR drill cannot pass, so there is no current restore proof; no workaround
**Introduced by:** unknown (the `_err` inside `hub_data_verify_ldap`; last full drill pass 2026-11-04)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23
**Prior art:** `docs/bugs/2026-10-16-cluster-up-ldap-seed-admin-bind-invalid-credentials.md` (dedup pass 1 by slug) — read, different root cause (cluster-up seed, not a restore)
**Filed:** 2026-11-23
**Detected by:** dr-drill runs 3 and 4 on m2-air (run 4 with `DR_DRILL_KEEP=1`), diagnosed by Claude read-only against the kept `k3d-dr-drill` cluster

## Observed

Phase 4 printed `V1 true`, `V2 true`, `V3 true`, then `make: *** [dr-drill] Error 1` (rc=2). No V4–V8 lines, no
report json, no error message in the pane. Same result in runs 3 and 4 (26m44s), so it is deterministic.

## Diagnosis (read-only, kept cluster, 2026-11-23)

- `openldap-0` Running; `ldapsearch -Y EXTERNAL` over `ldapi:///` returned rc=0 with 12 DNs, so the data restored.
- `ldapwhoami -x -D "cn=ldap-admin,dc=home,dc=org"` with the pod's `LDAP_ADMIN_PASSWORD` (set, non-empty, not printed)
  returned `ldap_bind: Invalid credentials (49)`. The restored database carries a different admin password from the
  `openldap-admin` Secret the drill cluster was given.

## Two defects

1. **Credential mismatch after restore.** The admin entry's `userPassword` comes from the backed-up data, while the pod
   env comes from the drill's Secret. The restore does not bring them back into agreement (or the Secret is
   restored from a different point than the LDAP data).
2. **`_err` exits the whole drill.** `scripts/plugins/hub_data.sh:1000` and `:1003` call `_err ...; return 1`, but
   `_err` (`scripts/lib/foundation/scripts/lib/system.sh:2114-2117`) runs `exit 1`, so the `return 1` is dead code.
   The exit bypasses `hub_data_verify`'s per-check `set +e` loop and dr-drill's phase 5 report; the EXIT trap tears the
   cluster down. The `ERROR:` line did not reach the pane.

## Expected

- A failing V check prints `V4 false` with a reason, the remaining checks run, and phase 5 writes the report.
- After restore the admin bind succeeds with the drill's `openldap-admin` password.

## Notes

- Kept cluster `dr-drill` is still up on m2-air for further diagnosis; delete it (`k3d cluster delete dr-drill`)
  before the next drill, or the preflight refuses (see `2026-11-23-dr-drill-teardown-ignores-failed-cluster-delete.md`).
