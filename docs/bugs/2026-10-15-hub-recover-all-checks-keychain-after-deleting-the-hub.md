# Bug: `make hub-recover-all` deletes the hub, then fails the Keychain preflight it could have run first

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN
**Priority:** P2 — the hub is left deleted with no rebuild; a manual resume (below) recovers it
**Approval:** explicit 2026-10-15 "did you file P2 bug" (operator, to "I'd file it as P2 once your hub is back")
**Severity:** high — a refusal that should cost nothing instead leaves the operator with no hub

## Symptom

Live run `20261016T012103Z` (2026-10-15, tmux, real TTY, export `20261016T003837Z`). The operator
typed the approval about 30 minutes after the prompt appeared. Teardown then ran to completion, and
the very next step refused:

```text
INFO[0024] Successfully deleted cluster k3d-cluster!
INFO: [acg-down] Local Hub cluster deleted
...
INFO: [acg-down] Done. Remote cluster and local Hub deleted.
ERROR: [hub-restore] needs an interactive terminal with Keychain access — run it from Terminal.app/iTerm, not Claude Code '!', nohup or ssh; try: security unlock-keychain
make[1]: *** [hub-recover] Error 2
make: *** [hub-recover-all] Error 2
```

`k3d cluster list` was empty afterwards. Nothing was rebuilt and nothing was restored.

## Root cause

`hub-recover-all` (`Makefile:95-107`) runs, in order:

1. `hub_data_recover_preflight` — checks the export, the target and a TTY, then waits for the typed
   approval (`scripts/plugins/hub_data.sh:1010`, approval at `_hub_data_recover_approval`).
2. `hub_data_recover_teardown` — deletes the hub (`scripts/plugins/hub_data.sh:1070`).
3. `make hub-recover`, whose first line is `bin/hub-restore --preflight-only` (`Makefile:62`).

The Keychain check exists only in step 3 (`bin/hub-restore:38`, `security show-keychain-info`).
Step 1 never runs it, so a locked login keychain is discovered after the destructive step. The
approval prompt has no time limit, so the keychain can also auto-lock while the operator is still
deciding, as it did here.

## Recovery when it happens

The run directory keeps the approval, the export path and the target, so resume without a second
teardown:

```bash
security unlock-keychain
security show-keychain-info && echo OK
make hub-recover
RESUME=<run_id> ./scripts/k3d-manager hub_data_recover
```

Do not rerun `make hub-recover-all`; it would start a new run.

## Fix

Run the `hub-recover` preflight after the approval and immediately before the teardown, so the
check reflects the keychain state at the moment of the destructive step. In `Makefile`
`hub-recover-all`:

```make
	run_id=$$(sed -n 's/^RUN_ID=//p' "$$preflight"); \
	test -n "$$run_id"; \
	bin/hub-restore --preflight-only; \
	K3DM_HUB_DATA_RECOVER_RUN_ROOT="$$run_root" ./scripts/k3d-manager hub_data_recover_teardown "$$run_id"; \
```

`set -e` is already in effect, so a non-zero preflight stops the recipe before the teardown. On
refusal, print the resume hint (unlock, then rerun `make hub-recover-all`; nothing was deleted).

## Files

- `Makefile`
- `scripts/tests/plugins/hub_data.bats` (or the suite that covers `hub-recover-all`)

## Definition of Done

- [ ] A test proves that a failing `bin/hub-restore --preflight-only` (stubbed) stops
      `hub-recover-all` before `hub_data_recover_teardown` runs, and that the teardown stub is
      never called. Check the test fails against the pre-fix `Makefile`.
- [ ] A passing preflight still reaches the teardown, `hub-recover` and the `RESUME` restore.
- [ ] `docs/howto` / guide page for hub recovery documents the resume sequence above.
- [ ] Commit message: `fix(hub-data): check Keychain access before hub-recover-all deletes the hub`
