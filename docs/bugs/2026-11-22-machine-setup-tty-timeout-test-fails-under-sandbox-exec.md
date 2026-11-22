# Bug: machine_setup.bats "tty_machine: timeout kills the fixture" fails under sandbox-exec

**Status:** OPEN — captured 2026-11-22, not triaged
**Priority:** P3
**Introduced by:** `abcde772` (v1.43.13, `tty_limited` helper)
**Should have been caught by:** offline test — the helper was never run under the sandbox that land and verifier runs use
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-22
**Prior art:** `docs/bugs/2026-10-31-machine-setup-tty-test-hangs-push-gate.md` and `docs/bugs/2026-11-07-machine-setup-tests-inherit-caller-tty.md` (exact-slug and keyword grep; `make find-similar-docs` unavailable on m4) — read, different root cause: those added the time limits; this is the time limit failing to kill under a sandbox
**Filed:** 2026-11-22
**Detected by:** Claude, verifying the web-console C r2 land `--test` set
**Affected:** `scripts/tests/bin/machine_setup.bats` (`tty_limited`, lines 984–1011; test `tty_machine: timeout kills the fixture and a short command completes`, test 187 in the C r2 land run)

## Symptom

```text
not ok 187 tty_machine: timeout kills the fixture and a short command completes
```

It fails in both C r2 land attempts (`.run/land-test.log`, `land-test.1.log`) and in Claude's verification runs under
`sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/sudo") (literal "/bin/launchctl"))'`.
It also fails on the base tree `1055db70` without the C r2 change, so it is not caused by C r2. Strays left behind:
`script` and the fixture's `sleep 300`, still alive well past the 5 s limit.

## Reproduction (m4, 2026-11-22, `/usr/bin/perl` 5.34.1)

`tty_limited` extracted into a script, run as `tty_limited 3 bash -c '/bin/sleep 1 | script -q /dev/null /bin/sleep 20'`:

| Run | Output | Time |
|---|---|---|
| no sandbox | `timed out after 3s`, rc 124 | 4 s |
| under the sandbox-exec profile above | `ps: Operation not permitted`, rc 1 | 20 s (the child ran to completion) |
| no pipe or `script`, no sandbox | `timed out after 3s`, rc 124 | 3 s |

## Cause (partly confirmed)

On timeout, `tty_limited` finds the processes to kill by running `ps -axo pid=,ppid=` (line 997). `/bin/ps` is
setuid root (`-rwsr-xr-x`), and under the sandbox profile it fails with "Operation not permitted", so the descendant
list holds only the top pid. `script` puts its child on a new pty session, so the process-group kill (`kill KILL -$pid`)
misses it as well. Not yet explained: why the helper exits 1 rather than 124 under the sandbox.

## Impact

Test-only. Every land or verification run started from a Claude session (whose Bash runs under a sandbox) gets this
red, and each attempt leaves a stray `sleep 300`. Lands either need the test excluded (an operator-approved gate
change) or must be run from the operator's own terminal.

## Fix direction

Find descendants without a setuid `ps` (for example, run the command in its own process group and have `script`'s
child killed through the pty, or use `pgrep -g`, or `proc_listchildpids` via a small helper), and make the helper exit
124 whenever the alarm fires. Add a test that runs `tty_limited` under the sandbox profile.
