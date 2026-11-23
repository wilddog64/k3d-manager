# Bug: hub_promote.bats TTY driver's fixed 10 s deadline fails test 34 under load

**Status:** OPEN — captured 2026-11-22
**Priority:** P3
**Introduced by:** `aa1196ed` (v1.43.15, `_run_promoter_tty` with `deadline = time.time() + 10`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** `docs/bugs/2026-11-11-hub-promote-non-tty-tests-hang-when-stdin-is-a-terminal.md` and `docs/bugs/2026-11-11-hub-promote-tty-test-hangs-on-interactive-stdin.md` — read, different root cause (those were a hang from an inherited TTY, fixed; this is a wall-clock budget); `make find-similar-docs` returned nothing on the M4.
**Detected by:** Claude, 2026-11-22, m4-air, during the remote-promote-2b land
**Severity:** test-only. A land or CI run can go red with no code defect.

## What happened

`hub_promote.bats` test 34, "G regression: non-TTY promoter test completes when suite stdin is a terminal", failed once in the
2b land (`land-test.2.log`, status not 0 at line 869). The same test passed in the earlier land attempt (`land-test.1.log`),
in three full-suite runs by Claude the same day, and five times in isolation (2–3 s each, load average about 2.3).

## Root cause (named, not yet proven by reproduction)

Test 34 runs a nested `bats -f 'N2: non-TTY'` under `script` with `alarm 60`. N2 calls `_run_promoter_tty`, whose pty driver gives the
promoter a fixed wall-clock budget of 10 s (`deadline = time.time() + 10`) before it gives up. Under land load (several suites
plus background daemons) the nested promoter can run past 10 s, and the driver's give-up path fails N2, so test 34 fails. The
failure output showed only the nested setup's harmless "cloned an empty repository" warning, so the exact exit path is not
captured.

## Fix direction

Make the driver wait on the child (reap with a generous ceiling, for example 60 s to match the outer alarm) instead of a short
fixed deadline, and print which path ended the wait so a future failure is diagnosable. Reproduce first by running the suite
under CPU load (for example, parallel `yes > /dev/null`) to confirm the 10 s path is the one that fails.
