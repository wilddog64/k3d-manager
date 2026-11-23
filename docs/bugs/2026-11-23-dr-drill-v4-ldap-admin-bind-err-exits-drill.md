# Bug: dr-drill dies silently at V4 — restored LDAP rejects the admin password and `_err` exits the drill

**Status:** OPEN — spec rev 1 for defect 2 (Fable review pending); defect 1 waiting on operator decision
**Priority:** P2 (proposed) — the DR drill cannot pass, so there is no current restore proof; no workaround
**Introduced by:** unknown (the `_err` inside `hub_data_verify_ldap`; last full drill pass 2026-11-04)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-23 (Fable spec review)
**Triage:** patch → v1.45.1 (operator, 2026-11-23: v1.45.1 = security and DR release)
**Branch:** k3d-manager-v1.45.1
**Intent approved:** pending
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

## Fix (spec rev 1, Claude, 2026-11-23) — defect 2 only

Defect 1 (which admin password wins after a restore) needs an operator decision (see Open question). Defect 2 is
independent and makes the drill report the failure instead of vanishing.

1. In `scripts/plugins/hub_data.sh`, the three `_err ...; return 1` inside V checks (`:994` Keycloak digest, `:1000`
   LDAP admin bind, `:1003` LDAP DN digest) become `printf 'ERROR: %s\n' '<same message>' >&2; return 1`. Same text,
   same stream, no `exit`.
2. No other `_err` in `hub_data.sh` changes: the `hub-recover` ones run outside the V loop and exit by design.
3. Result: `hub_data_verify` prints `V4 false`, runs V5 and V8, writes the report json; `bin/dr-drill` runs phase 5
   (report) and phase 6 (teardown) as for any failed check.

## External behaviour

In-repo only: `_err` is `printf 'ERROR: %s\n' "$*" >&2; exit 1` (`scripts/lib/foundation/scripts/lib/system.sh:2114-2117`),
so `return 1` after it never runs, and `exit` inside a function called from the `set +e` loop
(`hub_data.sh:1036-1053`) ends the whole script.

## Contract readers

| Where | Reads | Change |
|---|---|---|
| `scripts/plugins/hub_data.sh:1031-1055` `hub_data_verify` | rc of each V function | none (now actually gets rc 1) |
| `bin/dr-drill:220` `_dr_drill_verify_vault` | rc of `hub_data_verify` | none |
| `HUB_DATA_VERIFY_REPORT` json | V1..V8 booleans | V4 written as false instead of absent |
| `scripts/tests/plugins/hub_data.bats` | V functions | new cases |

## Acceptance

```yaml
must:
  M1: when the LDAP admin bind fails, hub_data_verify prints "V4 false", then V5 and V8 lines, and writes V4:false into the report json
  M2: the same for the LDAP DN digest mismatch (V4) and the Keycloak digest mismatch (V3)
  M3: each failure still prints its ERROR line with the same text as today
must_not:
  N1: any V check failure ends the calling shell (today _err exits)
  N2: hub-recover functions that exit by design change
evidence:
  - {id: E1, proves: [M1, M3, N1], kind: offline, intent: "You will see a test where the fake LDAP bind fails: the verifier prints V4 false with the ERROR line, then V5 and V8, and the report file has V4 false.", command: "bats scripts/tests/plugins/hub_data.bats", red: "today's tree: the run stops after V3 with exit 1, no V5 line"}
  - {id: E2, proves: [M2, N1], kind: offline, intent: "You will see the same for a wrong LDAP DN digest and a wrong Keycloak digest.", command: "same run", red: "today's tree: exits at the first failure"}
  - {id: E3, proves: [N2], kind: offline, intent: "You will see the whole hub_data suite pass unchanged, and a grep showing the hub-recover _err lines untouched.", command: "same run; git diff scripts/plugins/hub_data.sh touches only lines 994, 1000, 1003", red: "n/a"}
  - {id: E4, proves: [M1], kind: live, intent: "You will see the next operator drill on m2-air print V4 false and later lines and leave a report, rather than stopping silently after V3.", command: "make dr-drill (operator, m2-air)", red: "n/a (live)"}
interface:
  - "hub_data_verify_* signatures unchanged"
```

## Files

| File | Change |
|---|---|
| `scripts/plugins/hub_data.sh` | lines 994, 1000, 1003 |
| `scripts/tests/plugins/hub_data.bats` | E1, E2 |

## Routing

Luna, 1 logic line-set + 1 test. Same file as the empty-identity fix: one task for both (recommended), or serial.

## Open question (operator) — defect 1

After a restore, which admin password is the truth?
- (a) The backup's: the drill also restores the `openldap-admin` Secret from the export, so env and data agree.
  Matches a real recovery, where the old password is what users and Keycloak federation expect.
- (b) The drill's: after restore, reset the `cn=ldap-admin` `userPassword` to the Secret via `ldapmodify -Y EXTERNAL`.
  Simpler, but the drill no longer proves the backed-up credentials work.
Claude's recommendation: (a). First check, read-only, whether the export already carries the Secret (inventory list only, no values).
