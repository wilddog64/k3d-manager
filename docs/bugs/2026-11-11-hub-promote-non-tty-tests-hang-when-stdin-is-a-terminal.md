# Bug: hub-promote "non-TTY" tests hang forever when the runner's stdin is a terminal

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-11 (post-merge `/release-groom` triage with the other P3s; or fold into the next `hub_promote.bats` dispatch)
**Severity:** test-only. Under CI or `make test` stdin is not a terminal and the tests pass. Run from an interactive shell or an agent that holds a pty, the test blocks on the typed-confirmation `read` and never returns. Workaround: `bats scripts/tests/bin/hub_promote.bats < /dev/null`.
**Introduced by:** unknown (the N2 test and the unguarded `run` calls in `hub_promote.bats`)
**Should have been caught by:** review
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run (vector store context missing on the M4).
**Approval:** Claude, 2026-11-11 (found while watching dispatch `hub-promote-keeps-promoter-commits-r4`)
**Filed:** 2026-11-11
**Detected by:** Claude, 2026-11-11, m4-air

## What happened

Dispatch r4 (Flash 3.8 through agy, which gives its shell a pty) ran `bats scripts/tests/bin/hub_promote.bats`.
Test 7, then test 20, then a `bats -f non-TTY` rerun each sat for 5 to 21 minutes on a scratch-repo
`k3dm-hub-promote promote k3d-manager-v1.43.15` with no child processes, state `S+`, stdin `/dev/ttys006`. An
abandoned r2 worker had been stuck on the same test 7 for about 4h45m. Killing the scratch process let the suite continue.

## Root cause

`hub_promote.bats:302-305` (N2 "non-TTY ... refuse") runs the promoter with `run env ... k3dm-hub-promote promote ...`
and no stdin redirect, so it inherits the runner's stdin. The test assumes that stdin is not a terminal. When it is one,
the promoter's TTY check passes and it waits at the typed confirmation.

## Fix

Give every promoter call in `hub_promote.bats` an explicit stdin: `< /dev/null` for the non-TTY cases, the existing
`_run_promoter_tty` helper for the TTY cases. Add a check that runs the N2 case under a pty (`script -q /dev/null bats -f N2 ...`)
and finishes within a timeout. Acceptance block to be added before dispatch.
