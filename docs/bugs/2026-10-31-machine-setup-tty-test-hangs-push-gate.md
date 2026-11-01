# Bug: a machine_setup.bats pseudo-terminal test can hang for 43 minutes, and the push gate waits with it

**Status:** FIXED — `29e6c3af` (Codex; Claude review, independent verifier PASS); live check pending
**Priority:** P2
**Severity:** medium — an intermittent hang stalls every push and land that runs the suite; nothing reports it
**Approval:** operator, 2026-10-31 ("go ahead to dispatch these two"), in reply to Claude's proposal to file it as P2
**Filed:** 2026-10-31
**Detected by:** Claude, pushing `18c48507` on `k3d-manager-v1.43.13`
**Affected:** `scripts/tests/bin/machine_setup.bats` (`tty_machine`, test 32 `N9: no pull without FROM, without a terminal, or in check mode`); `scripts/ci/fast_gate.sh`
**Branch:** `k3d-manager-v1.43.13`
**Depends on:** `docs/bugs/2026-10-31-pre-push-gate-from-linked-worktree-writes-into-real-repo.md` (also edits `scripts/ci/fast_gate.sh`; land that one first and rebase this one on it)

## Observed failure

The pre-push fast gate for `18c48507` sat for 43 minutes on `machine_setup.bats` test 32. `ps` showed `k3dm-machine-setup --role console` alive under `script -q /dev/null <wrapper>`, waiting on the pseudo-terminal, with the hook's stdin at `/dev/null`. Claude killed the setup process; the test then PASSED and the push completed. Earlier pushes and a land ran the same test without a hang, so it is intermittent.

## Root cause

`tty_machine` runs `bash -c "/bin/sleep 3 | script -q /dev/null '$wrapper'"` with no time limit. When the setup under the pty blocks on a terminal read after the 3-second pipe has closed (N9 runs with the default `--secrets ask`, which prompts `[y/N]`), nothing ends it. The fast gate runs suites with no per-suite time limit and prints only after a suite exits, so a hang looks the same as a slow suite. Which read blocks, and why only sometimes, is not established; the fix must not depend on finding it.

## Fix

1. `tty_machine` puts a hard time limit on the `script` run (default 60 s, overridable with `TTY_MACHINE_TIMEOUT`). On expiry it kills the whole process group, including `k3dm-machine-setup` under the pty, and fails the test with a message that names the timeout. macOS has no `timeout(1)` by default, so use a portable form (for example a `perl` alarm, or a background killer on the process group).
2. `scripts/ci/fast_gate.sh` puts a per-suite time limit on each suite (default 900 s, overridable with `FAST_GATE_SUITE_TIMEOUT`). On expiry it kills the suite's process group, fails the gate, and names the suite and the limit. A suite that finishes in time is unaffected.
3. Do not change what N9, M3/M4, N4, M7 or M9 assert.

## Files

- `scripts/tests/bin/machine_setup.bats`
- `scripts/ci/fast_gate.sh`
- `scripts/tests/lib/fast_gate.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not skip or delete the pseudo-terminal tests.
- Do not "fix" it by raising the 3-second sleep or feeding answers on stdin; a hang must end in a failure, not a longer wait.
- Do not leave a killed `k3dm-machine-setup` or `script` process running after the test fails.

## Acceptance

```yaml
must:
  M1: a tty_machine run whose command never exits fails within TTY_MACHINE_TIMEOUT plus 10 s, with output naming the timeout
  M2: a fast-gate suite that never exits fails the gate within FAST_GATE_SUITE_TIMEOUT plus 10 s, naming the suite and the limit
  M3: the existing machine_setup.bats tty tests (M3/M4, N4, M7, M9, N9) pass unchanged when the command exits normally
must_not:
  N1: after a timeout, no process from the hung command (script, the wrapper, k3dm-machine-setup or a stub) is still running
  N2: a suite or tty run that finishes under its limit is never killed or marked failed (paired control for M1 and M2)
evidence:
  E1:
    proves: [M1, N1, N2]
    kind: offline
    intent: >-
      You will see tty_machine pointed at a wrapper that sleeps forever under the pty, fail inside the limit with
      the timeout named, and a pgrep afterwards that finds none of its processes; and a wrapper that exits in 1 s
      pass. The fixture first asserts that it runs the scratch FIXROOT copy, not the real bin/k3dm-machine-setup.
      The hang test is red against the pre-fix helper (run it with a short outer limit so the red run ends).
    what: bats scripts/tests/bin/machine_setup.bats with TTY_MACHINE_TIMEOUT=5
  E2:
    proves: [M2, N1, N2]
    kind: offline
    intent: >-
      You will see the fast gate run on a scratch repository with a probe suite that never exits, fail inside
      FAST_GATE_SUITE_TIMEOUT=5 naming that suite, and leave no probe process; and a probe that exits in 1 s pass.
      The hang test is red against the pre-fix gate.
    what: bats scripts/tests/lib/fast_gate.bats
  E3:
    proves: [M3]
    kind: offline
    intent: You will see the full machine_setup.bats suite green on macOS outside the Codex sandbox.
    what: bats scripts/tests/bin/machine_setup.bats, run by Claude
interface:
  - scripts/tests/bin/machine_setup.bats tty_machine (env TTY_MACHINE_TIMEOUT)
  - scripts/ci/fast_gate.sh [BASE] (env FAST_GATE_SUITE_TIMEOUT)
```
