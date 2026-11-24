# Bug: dr-drill dies silently at V4 — restored LDAP rejects the admin password and `_err` exits the drill

**Status:** OPEN — defect 2 LANDED `da956fbd` (2026-11-23, Sonnet acceptance verify pass x2; E4 live pending); defect 1 spec written `docs/plans/v1.45.1-dr-drill-v4-ldap-resync.md` (intent approval and pre-dispatch probe pending)
**Priority:** P2 (proposed) — the DR drill cannot pass, so there is no current restore proof; no workaround
**Introduced by:** unknown (the `_err` inside `hub_data_verify_ldap`; last full drill pass 2026-11-04)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23 (defect 1 intents and the drill-cluster repoint probe)
**Triage:** patch → v1.45.1 (operator, 2026-11-23: v1.45.1 = security and DR release)
**Branch:** k3d-manager-v1.45.1
**Intent approved:** operator, 2026-11-23
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

## Fix (spec rev 2, Claude, 2026-11-23) — defect 2 only

Defect 1 (which admin password wins after a restore) needs an operator decision (see Open question). Defect 2 makes
the drill report the failure instead of vanishing.

**Rev 1 was wrong (Fable).** The exit does not come from the `_err` at `:1000`. `_hub_data_ldap_admin_bind`
(`scripts/plugins/hub_data.sh:220-222`) runs `"$@" ... exec ... >/dev/null 2>&1` in the current shell, with
`"$@"` = `_kubectl --context <ctx>`. Without `--no-exit`, a failed `kubectl exec` goes through `_run_command`'s failure
handler to `_err` → `exit 1` (`scripts/lib/foundation/scripts/lib/system.sh:117-131,201-204`), inside the helper, with
its stderr discarded. That is why the pane showed no ERROR line. Fable reproduced it offline: today rc 1 silent;
rev 1's change applied, still rc 1 silent; with `--no-exit`, ERROR line and return 1.

1. `hub_data.sh:1000`: call the bind as `_hub_data_ldap_admin_bind _kubectl --no-exit --context "$context"`
   (`--no-exit` must be the first flag; foundation `_kubectl` only accepts it there, `system.sh:1294-1301`).
2. `hub_data.sh:1014` (V5 placement): the `_kubectl --context ... wait --for=condition=Ready` call gets `--no-exit` as
   its first flag. Today a pod not Ready exits the drill before `V5 false`.
3. `hub_data.sh:994, 1000, 1003`: `_err ...; return 1` → `printf 'ERROR: %s\n' '<same message>' >&2; return 1`.
   Same text, same stream, no exit.
4. Unchanged: the `hub-recover` `_err` calls outside the V checks (they exit by design); V2 (`:711-737`, runs in a
   subshell), the V3/V4 count and digest helpers (inside `$(...)`), V8 (`$(...) || return 1`), and V1's
   `_hub_data_pin_context` (skipped in the drill, `:979-980`). Fable checked each.
5. **Where the result shows.** In the drill, the V lines from the bug ("V1 true / V2 true / V3 true") are
   `hub_data_verify`'s output inside the drill's own V2 check (`bin/dr-drill:220`). The drill's V3 and V4 call
   `hub_data_verify_keycloak` / `hub_data_verify_ldap` directly (`bin/dr-drill:221-226`). After the fix, a bind
   failure gives drill V2=false and V4=false in `~/.k3dm/dr-drill/<ts>.json`, and `hub_data_verify` writes V4:false to
   `HUB_DATA_VERIFY_REPORT` (default `/tmp/k3dm-hub-checks.json`, `hub_data.sh:1035`).

## External behaviour

In-repo only. `_err` is `printf 'ERROR: %s\n' "$*" >&2; exit 1` (`system.sh:2114-2117`); `_run_command` without
`--no-exit` ends in `_err` on a non-zero rc (`system.sh:117-131,201-204`); `exit` inside a function ignores the
loop's `set +e` (`hub_data.sh:1036-1053`). The drill calls checks through `if "$@"` (`bin/dr-drill:114`).

## Contract readers

| Where | Reads | Change |
|---|---|---|
| `scripts/plugins/hub_data.sh:1031-1055` `hub_data_verify` | rc of each V function | none (now gets rc 1) |
| `scripts/plugins/hub_data.sh:220-222` `_hub_data_ldap_admin_bind` | `"$@"` kubectl wrapper | none (caller passes `--no-exit`) |
| `scripts/plugins/hub_data.sh:1218-1220` hub-recover step 8 | `hub_data_verify` | none; a failed check now reaches `_hub_data_run_step` instead of exiting |
| `bin/dr-drill:220` `_dr_drill_verify_vault` (drill V2) | rc of `hub_data_verify` | none |
| `bin/dr-drill:221-226` `_dr_drill_verify_keycloak` / `_ldap` (drill V3, V4) | rc of the V functions | none |
| `bin/dr-drill:60-76,78` `_dr_drill_kubectl` | `--no-exit` passthrough | none (already accepts it) |
| `HUB_DATA_VERIFY_REPORT` json | V booleans | V4/V5 false written instead of absent |
| `scripts/tests/plugins/hub_data.bats:1367-1375` B4-R3 | stubs `_hub_data_ldap_admin_bind` | unchanged; stays green |

## Acceptance

```yaml
must:
  M1: when the LDAP admin bind's kubectl exec fails, hub_data_verify prints "V4 false" with the ERROR line, then V5 and V8 lines, and writes V4:false to HUB_DATA_VERIFY_REPORT
  M2: the same for an LDAP DN digest mismatch (V4), a Keycloak digest mismatch (V3), and a pod that never becomes Ready (V5)
  M3: each failure prints its ERROR line with the same text as today
must_not:
  N1: any V check failure, including a failing kubectl inside a check helper, ends the calling shell
  N2: hub-recover functions that exit by design change
evidence:
  - {id: E1, proves: [M1, M3, N1], kind: offline, intent: "You will see a test where a fake kubectl layer exits the shell on any failure, the way the real one does, and the LDAP bind fails: the verifier still prints V4 false with the ERROR line, then V5 and V8, and the report file has V4 false.", command: "bats scripts/tests/plugins/hub_data.bats", red: "today's tree, and rev 1's three-line change: the run exits silently after V3"}
  - {id: E2, proves: [M2, N1], kind: offline, intent: "You will see the same for a wrong LDAP DN digest, a wrong Keycloak digest, and a pod that never becomes Ready.", command: "same run", red: "today's tree: exits at the first failure (the V5 case exits in _kubectl wait)"}
  - {id: E3, proves: [N2], kind: offline, intent: "You will see the whole hub_data suite pass with no existing assertion changed, and the diff of hub_data.sh limited to lines 994, 1000, 1003 and 1014.", command: "same run; git diff --stat and -U0 of scripts/plugins/hub_data.sh", red: "n/a"}
  - {id: E4, proves: [M1], kind: live, intent: "You will see the next operator drill on m2-air print V4 false and the later checks, and leave a drill report with V2 and V4 false, rather than stopping silently after V3.", command: "make dr-drill (operator, m2-air)", red: "n/a (live)"}
interface:
  - "hub_data_verify <inventory> [ns] [context]: unchanged; E1/E2 drive it directly"
  - "hub_data_verify_* and _hub_data_ldap_admin_bind signatures unchanged"
```

**Test seam (required).** E1 and E2 stub at `_kubectl`, not at `_hub_data_ldap_admin_bind`, using the hard-exit model
already in `hub_data.bats:866`: `_kubectl() { [[ "$1" == --no-exit ]] && return 1; ...; exit 1; }` (return 1 when
called soft, exit when called hard). They call `hub_data_verify` itself under `run` and assert the V5 and V8 lines.
A stub at the helper (as B4-R3 does) goes green on rev 1's broken fix.

## Files

| File | Change |
|---|---|
| `scripts/plugins/hub_data.sh` | lines 994, 1000, 1003, 1014 |
| `scripts/tests/plugins/hub_data.bats` | E1, E2 |

## Routing

Luna. Serial after the empty-identity fix (same two files), which landed as `77d5a836` on 2026-11-23; dispatch from that base.

## Open question (operator) — defect 1

After a restore, which admin password is the truth?
- (a) The backup's: the drill also restores the `openldap-admin` Secret from the export, so env and data agree.
  Matches a real recovery, where the old password is what users and Keycloak federation expect.
- (b) The drill's: after restore, reset the `cn=ldap-admin` `userPassword` to the Secret via `ldapmodify -Y EXTERNAL`.
  Simpler, but the drill no longer proves the backed-up credentials work.
Claude's recommendation: (a). First check, read-only, whether the export already carries the Secret (inventory list only, no values).

## Operator decisions (2026-11-23)

- Defect 1: option (a), restore the `openldap-admin` Secret from the export (Claude's recommendation, accepted). Spec for defect 1 follows after a read-only inventory check; it dispatches after the defect 2 task lands (same file).

## Defect 1 inventory result (read-only, Claude, 2026-11-23)

The export holds no Kubernetes Secrets (three PVC tarballs plus `inventory.json`), so option (a) cannot restore the
Secret literally. It does not need to: `openldap-admin` is an ExternalSecret from Vault `ldap/openldap-admin`, and the
restored Vault holds the backup's password. On the kept cluster, ESO last synced at 13:30:16Z (the drill's fresh Vault)
and has been `SecretSyncedError` since the 13:47:59Z restore. SecretStore `vault-kv-store` is `InvalidProviderConfig`,
because the restored Vault's `auth/kubernetes/config` names the real hub. `hub_recover` repoints it (step 6); the drill
does not. Spec: `docs/plans/v1.45.1-dr-drill-v4-ldap-resync.md` (repoint, force-sync, restart openldap after unseal).
