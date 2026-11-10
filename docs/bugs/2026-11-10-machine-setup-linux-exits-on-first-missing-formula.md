# Bug: Linux control setup exits on the first formula that is not installed yet

**Status:** OPEN
**Priority:** P2
**Waiting on:** dispatch — since 2026-11-10 (WIP 3/3)
**Introduced by:** `4bd764b9` (v1.43.15, `bin/k3dm-machine-setup:102`)
**Should have been caught by:** offline test (the Linux cases in `scripts/tests/bin/machine_setup.bats` stay green; why is part of the fix)
**Prior art:** `make find-similar-docs` not run (vector store unreachable from the M4, 2026-11-10); exact-slug glob: none
**Severity:** blocks the v1.43.15 control-node feature. On a fresh Linux node, `make machine-setup ROLE=control` exits 2 with no message right after `homebrew ok`; no formula is installed, no repo cloned. Introduced in the open release, so it blocks the release PR.
**Approval:** operator, 2026-11-10: "go ahead to file P3 and dispatch to Luna" (given for the Vagrant P3 while this was being traced; same live run)
**Intent approved:** operator, 2026-11-10
**Intent approval words:** "go ahead for your two suggestions"
**Dispatch:** operator go 2026-11-10 ("go ahead for your two suggestions": dispatch to Luna, first), `--agent codex --model gpt-6-luna`, slug `machine-setup-linux-missing-formula`; waits for a WIP slot
**Filed:** 2026-11-10
**Detected by:** Claude, 2026-11-10, live E3 of `docs/plans/v1.43.15-control-node-linux.md` (Vagrant VM on the M4)
**Branch:** `k3d-manager-v1.43.15`
**Release:** v1.43.15

## Symptom

Vagrant `bento/ubuntu-24.04` 202502.21.0 (aarch64, kernel 6.8.0-53) on the M4, 2026-11-10, after the provision-homebrew
prereqs role (`changed=0` on rerun), as `k3dm-control`: `make machine-setup ROLE=control` prints `homebrew ok`, then
`make: *** [Makefile:1787: machine-setup] Error 1`, `setup-rc=2`. `bash -x bin/k3dm-machine-setup --role control` ends at:

    + grep -Fqx formula:gh .../brew.control.linux-skip.list
    + _run_command -- brew list --formula gh

## Root cause

`bin/k3dm-machine-setup:102` probes with `_run_command -- brew list --formula "$name" >/dev/null 2>&1`. `_run_command`
without `--soft` calls `_err` on a non-zero exit (lib-foundation `scripts/lib/system.sh`,
`_run_command_handle_failure`), which exits the script. `brew list` exits 1 for a formula that is not installed, which
is every formula on a fresh node, so the script dies on the first one, inside the `if`. The `2>&1` redirect hides the
`_err` message. The macOS path (`:246`) calls `brew list` directly and is not affected. Line 103 (`_run_command -- brew
install`) has the same shape: a failed install exits instead of reporting `missing`.

## Fix

Probe without the exiting wrapper (`brew list --formula "$name"`, as `:246` does, or `_run_command --soft --quiet`), and
make a failed install report `brew:<name> missing` and set `failed=1` instead of exiting. Find why the Linux cases did not
catch this and make one of them fail on today's code.

## Files

| File | Change |
|---|---|
| `bin/k3dm-machine-setup` | lines 102-103 |
| `scripts/tests/bin/machine_setup.bats` | Linux case with a formula not yet installed |

## Contract readers

None: no shared contract changes (same report lines, same exit codes on success and on a recorded failure).

## Acceptance

```yaml
must:
  - id: M1
    text: "On Linux with --role control, a formula that brew list reports missing is installed with brew install and reported 'installed'; setup goes on to the next formula."
  - id: M2
    text: "A formula whose brew install fails is reported 'missing', setup continues through the rest of the list and the repos, and exits non-zero at the end."
must_not:
  - id: N1
    text: "Setup never exits before the end of the formula list because one formula is absent or fails to install."
evidence:
  - {id: E1, proves: [M1, M2, N1], kind: offline, intent: "You will see machine_setup.bats run Linux setup with a brew stub (exit codes from the 2026-11-10 VM: brew list --formula gh exits 1) where gh is missing and installs, and one formula fails to install, and assert gh 'installed', the failing one 'missing', the repo step reached, and a non-zero exit; the test fails on today's script."}
  - {id: E2, proves: [M1], kind: live, intent: "Claude reruns the control-node E3 on a fresh Vagrant VM and sees every Linux formula of brew.control.list reported ok or installed, then the repos cloned."}
interface:
  - "bin/k3dm-machine-setup --role control (Linux, uname stubbed)"
  - "make machine-setup ROLE=control"
```

## Worker definition of done

- Find and state why the current Linux cases pass; the new case must fail on today's script (show it).
- Mutant shown red: restore `_run_command --` around the `brew list` probe.
- Run `bats scripts/tests/bin/machine_setup.bats scripts/tests/bin/machine_setup_acceptance.bats`; paste command, rc and
  proving lines. macOS results unchanged. Leave changes uncommitted; Claude reviews and lands.
