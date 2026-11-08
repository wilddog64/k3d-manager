# Bug: machine_setup.bats "without a TTY" tests hang when the caller has a terminal

**Status:** VERIFIED — `ae01d46b` (Luna; Claude fixed the run_machine indent and resolved the rebase onto F1's REAL_PYTHON3 change), 2026-11-07. Test-only fix: E1 red pre-fix (prompted, killed at 90 s, rc 142) and green after; E2 89/89 with </dev/null and 89/89 inside script(1), run by Claude outside any agent sandbox
**Fix commit:** `ae01d46b`
**Priority:** P3
**Severity:** low — test-only; a gate run under an agent that allocates a terminal hangs with no output and no limit
**Approval:** operator, 2026-11-07 ("go ahead to kill the hung test process, file P3 bug and dispatch to Luna")
**Assigned:** Luna
**Filed:** 2026-11-07
**Detected by:** Claude, while checking why the `cost-attribution-coverage` Flash dispatch was still running after 4 hours
**Affected:** `scripts/tests/bin/machine_setup.bats` (`run_machine` helper; first seen in test `machine setup: missing secrets do not prompt without a TTY`)
**Branch:** `k3d-manager-v1.43.15`
**Depends on:** `docs/bugs/2026-11-07-e2e-results-never-reach-m5-hub.md` (its fix also edits `scripts/tests/bin/machine_setup.bats`; land that one first and rebase this one on it)
**Related:** `docs/bugs/2026-10-31-machine-setup-tty-test-hangs-push-gate.md` (fixed `tty_machine`, the pseudo-terminal helper, with a time limit; this bug is the other helper)

## Observed failure

The Flash dispatch for `docs/plans/v1.43.15-cost-attribution-coverage.md` finished editing its six files and then ran
its gate, `make test-bin`. The gate sat at 0% CPU for 3 h 41 min. The process tree ended at
`bash /tmp/bats-run-X7t966/test/733/project/bin/k3dm-machine-setup --role console`, test
`machine setup: missing secrets do not prompt without a TTY`. `lsof` showed its fd 0 as `/dev/tty` (CHR 2,0). Claude
killed PID 72927 with the operator's approval, and bats carried on.

## Root cause

`run_machine` (`scripts/tests/bin/machine_setup.bats:271-273`) runs `bin/k3dm-machine-setup` with the caller's stdin.
The tests that use it are written for "no terminal". The test name says so, and the script decides whether to prompt
with `[[ -t 0 ]]` (`bin/k3dm-machine-setup:116`, `:367`, `:391`, `:483`). Under CI or a plain pipe that holds, but
`agy` gives its children a real terminal. Then `-t 0` is true, `check_secrets` prints `Run setup command now? [y/N]`
to `/dev/tty`, and `read -r answer </dev/tty` (`:397`) waits for an answer that never comes. `run_machine` has no time
limit, unlike `tty_machine` after the 2026-10-31 fix.

`scripts/tests/bin/machine_setup_acceptance.bats:133` already runs the script with `< /dev/null`, which is why that
suite does not hang the same way.

## Fix

1. `run_machine` runs `bin/k3dm-machine-setup` with stdin from `/dev/null`, so every test that uses it sees no
   terminal whatever the caller has. That is the premise those tests are written for.
2. Do not change `tty_machine`, nor what any existing test asserts.
3. Any other direct call of `"$FIXROOT/bin/k3dm-machine-setup"` in `machine_setup.bats` outside `tty_machine` gets
   the same `< /dev/null`. List each one you change in your final message.

## Files

- `scripts/tests/bin/machine_setup.bats`

## What NOT to do

- Do not edit `bin/k3dm-machine-setup`. The `-t 0` checks are correct for real use.
- Do not add a time limit to `run_machine` in place of fixing stdin: a time limit turns a hang into a slow failure,
  and the test would still be testing the wrong thing.
- Do not change `tty_machine` or `scripts/ci/fast_gate.sh`.
- Do not skip or delete a test.
- Do not run git add, commit or push, and do not touch `memory-bank/`.

## Acceptance

```yaml
must:
  M1: every machine_setup.bats test that uses run_machine runs bin/k3dm-machine-setup with a stdin that is not a terminal, even when bats itself runs under a pseudo-terminal
  M2: the full machine_setup.bats suite passes on macOS both with stdin from /dev/null and when the whole bats run is wrapped in script(1) so it has a terminal
must_not:
  N1: run under a pseudo-terminal, "machine setup: missing secrets do not prompt without a TTY" never prompts and never blocks, and it finishes in under 60 s
  N2: the tty_machine tests (M3/M4, N4, M7, M9, N9) still see a terminal and keep their prompt behaviour (paired control for N1; the fix must not stop terminals reaching tests meant to have one)
evidence:
  E1:
    proves: [M1, N1]
    kind: offline
    intent: >-
      You will see the one test run with bats wrapped in `script -q /dev/null`, under an outer limit of 90 s, pass
      within the limit after the fix; and the same command against the pre-fix helper hit the outer limit (red). The
      fixture first asserts that bats has a terminal (for example `[ -t 0 ]` in a probe run the same way) so the red
      run is not vacuous.
    what: bats --filter 'missing secrets do not prompt without a TTY' scripts/tests/bin/machine_setup.bats, inside script(1)
  E2:
    proves: [M2, N2]
    kind: offline
    intent: >-
      You will see the whole machine_setup.bats green twice, once with </dev/null and once inside script(1), with
      the tty_machine tests among the passes.
    what: bats scripts/tests/bin/machine_setup.bats, run by Claude outside any agent sandbox
interface:
  - scripts/tests/bin/machine_setup.bats run_machine
  - scripts/tests/bin/machine_setup.bats tty_machine
```
