# Bug: `make hub-cutover-forwards` ignores the old host in the cutover report, so the documented command fails

**Status:** LANDED `c151bcb1`, offline verification recorded 2026-11-06 (independent suite 12/12 on the landed commit, 6 red on pre-fix `2394272d`, 5 mutants killed). Live E2 open: `make hub-cutover-verify` on the M5 with no variable and no `old-host` file.
**Priority:** P3
**Severity:** low. The documented command stops with a clear message, and setting `HUB_OLD_HOST` works around it.
**Approval:** Filing: Claude, 2026-11-06, told the operator when reporting the failed rollout. Dispatch: operator, 2026-11-06 ("please dispatch P2 and P3 to Luna").
**Filed:** 2026-11-06
**Detected by:** Operator, running the tunnel fix rollout on the M5, 2026-11-06
**Affected:** `bin/hub-cutover` (host resolution for `--verify`, `--forwards`, `--rollback`)
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-06-hub-cutover-verify-fails-forever-after-old-cluster-is-stopped.md`

## Observed failure

On the M5, 2026-11-06, `make hub-cutover-forwards` printed `hub-cutover: set HUB_OLD_HOST to the old hub (e.g. HUB_OLD_HOST=old-hub.local)`. `docs/howto/m5-hub-migration.md` gives the command with no variable.

## Root cause

Those three modes read the host only from `$STATE_DIR/old-host`. That file is absent on the M5 (`hub-cutover-report.json`, `old-argocd-controller-replicas` and `stopped-on-old` exist), and it is not known why. The state directory's `hub-cutover-report.json` has `old_host: m4-air.local` in all seven rows, so the host is on record.

## Fix

In those three modes, when `HUB_OLD_HOST` is empty and `old-host` is absent, take `old_host` from the last row of `$STATE_DIR/hub-cutover-report.json`. Validate it with the same host pattern used for `NEW_HOST` before use. If it is absent or invalid, print today's message and exit 2. `HUB_OLD_HOST` and `old-host` keep their precedence. Do not write `old-host`.

## Files

- `bin/hub-cutover`
- `scripts/tests/bin/hub_cutover.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "With HUB_OLD_HOST unset, old-host absent and a report row naming a valid host, --verify, --forwards and --rollback use that host."
  - id: M2
    text: "HUB_OLD_HOST wins over old-host, and old-host wins over the report."
must_not:
  - id: N1
    text: "An old_host value failing the host pattern is never passed to ssh; the run exits 2 (paired with M1)."
  - id: N2
    text: "With no report and no old-host, the run prints today's message and exits 2 with no ssh call."
  - id: N3
    text: "The run does not create or change old-host."
evidence:
  - {id: E1, proves: [M1, M2, N1, N2, N3], kind: offline, text: "BATS with HOME in BATS_TEST_TMPDIR (asserted first) and an ssh stub logging the host. M1 red on the pre-fix commit; each must_not red by a mutant."}
  - {id: E2, proves: [M1], kind: live, text: "Operator on the M5: make hub-cutover-verify with no variable reaches the old host m4-air.local."}
interface:
  - "bin/hub-cutover [--verify|--forwards|--rollback]"
  - "env: HOME, HUB_OLD_HOST, HUB_CUTOVER_STATE_DIR, PATH (ssh stub)"
```
