# Bug: `make hub-recover-all` deletes the hub, then fails the Keychain preflight it could have run first

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Status:** VERIFIED — Claude offline: tests green, new tests red on the old code, mutations red. Awaiting live proof. Was: IMPLEMENTED — landed `e5b93aee` (Codex `8b6cfb26`; Claude hardened the B4-23 negated grep with `|| false`, verified 118/118 and own mutation red). Pending the 2026-10-29 live drill.
**Priority:** P2 — the hub is left deleted with no rebuild; a manual resume (below) recovers it
**Approval:** explicit 2026-10-15 "you can dispatch four recovery fixes to codex" (operator)
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
check reflects the keychain state at the moment of the destructive step.

### F1 — `Makefile`, `hub-recover-all`

Old:

```make
	test -n "$$run_id"; \
	K3DM_HUB_DATA_RECOVER_RUN_ROOT="$$run_root" ./scripts/k3d-manager hub_data_recover_teardown "$$run_id"; \
```

New:

```make
	test -n "$$run_id"; \
	bin/hub-restore --preflight-only || { echo "[hub-recover] preflight refused before teardown — nothing was deleted; run security unlock-keychain, then rerun make hub-recover-all" >&2; exit 2; }; \
	K3DM_HUB_DATA_RECOVER_RUN_ROOT="$$run_root" ./scripts/k3d-manager hub_data_recover_teardown "$$run_id"; \
```

`bin/hub-restore --preflight-only` checks the TTY and `security show-keychain-info` only. The
kube-context and root-owned-directory checks run only without `--preflight-only`, so it passes
while the hub is still up.

### F2 — tests, `scripts/tests/plugins/hub_data.bats`

The existing recipe tests (`recover B4-20`, both `recover B4-21` recipe tests, `recover B4-22`)
run the real Makefile against a copied repo. Each copy now also needs an executable stub
`bin/hub-restore` that appends `hub-restore $*` to `$CALL_LOG` and exits 0. Update the expected
call sequences to include `hub-restore --preflight-only` between the preflight and
`hub_data_recover_teardown`.

Add `recover B4-23: keychain preflight refusal stops hub-recover-all before teardown`. The stub
`bin/hub-restore` exits 2. Assert `status` 2, `$CALL_LOG` contains `hub-restore --preflight-only`,
`$CALL_LOG` does not contain `hub_data_recover_teardown`, `hub-recover` or `hub_data_recover`, and
the output contains `nothing was deleted`.

Mutation check: delete the F1 line from the copied Makefile in a snapshot; show B4-23 red; restore
and `cmp`.

### F3 — docs

In `docs/howto/hub-dr-drill.md`, in the recovery runbook, note that `hub-recover-all` re-checks
Keychain access just before the teardown and refuses with nothing deleted if it is locked.

## Files

- `Makefile`
- `scripts/tests/plugins/hub_data.bats`
- `docs/howto/hub-dr-drill.md`

## Definition of Done

- [ ] B4-23 passes and is shown red under the F2 mutation.
- [ ] The updated B4-20/21/22 pass: a passing preflight still reaches the teardown, `hub-recover` and the `RESUME` restore.
- [ ] `scripts/tests/plugins/hub_data.bats` and `scripts/tests/plugins/vault_dr_shards.bats` are fully green.
- [ ] `docs/howto/hub-dr-drill.md` documents the check and the resume sequence above.
- [ ] Commit message: `fix(hub-data): check Keychain access before hub-recover-all deletes the hub`

## Live verification — scheduled 2026-10-29

Operator asked 2026-10-15 for a second rebuild two weeks after run `20261016T012103Z` to prove
the fix live. Needs the fix landed and green first; move the date if it is not.

1. `make hub-data-export` — a fresh export, under 24h old for the snapshot guard.
2. Negative check: `security lock-keychain`, then `make hub-recover-all` and approve. It must
   refuse before the teardown, and `k3d cluster list` must still show `k3d-cluster`.
3. `security unlock-keychain`, then `make hub-recover-all` again: teardown, rebuild and restore in
   one run with no manual resume.
4. Claude verifies: `COMPACT deleted` about every 5 minutes, the run report green,
   `HubKineCompactionStalled` resolved, SSO login to Grafana and ArgoCD.
