# e2e M2 preflight reads 0 GiB free disk when GNU `df` is first on PATH, so Hermes skips the daily e2e

**Status:** OPEN — captured 2026-11-25
**Priority:** P2 (daily Hermes e2e on M2 is skipped every slot; workaround: drop `gnubin` from M2's non-interactive PATH)
**Introduced by:** `62c9ff27` (v1.27.0, the `df -g` disk probe) meeting a `gnubin` entry in M2's `~/.zshenv` (date unknown)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** not run (`make find-similar-docs` vector store unreachable from M4; exact-slug glob found nothing; `ls docs/bugs | grep -i m2` read: no disk-probe doc)

## Symptom

Slack, 2026-11-25 04:56: `Hermes e2e 2026-11-25: skipped — M2 runner unavailable after 6 attempts` (`bin/k3dm-hermes:445`).

Read-only reproduction from M4, 2026-11-25: `./scripts/k3d-manager e2e_runner_preflight m2` prints
`reason=disk free 0GiB below floor 40GiB` / `status=capacity_disk`.

## Cause

`_e2e_remote_probe` (`scripts/plugins/e2e_remote.sh:189-190`) runs `df -g` over SSH and falls back to `disk_gb=0` when it prints
nothing. On M2 (2026-11-25, read-only SSH capture):

- `command -v df` → `/opt/homebrew/opt/coreutils/libexec/gnubin/df` (`df (GNU coreutils) 9.12`); `~/.zshenv` puts `gnubin` on PATH for
  non-interactive shells (the zshdotfiles repo head comments the coreutils path out since `359b8cb`, 2019, so this is a local M2 edit);
- `df -g "$HOME"` → `df: invalid option -- 'g'` (BSD-only flag);
- `/bin/df -g "$HOME"` → 308 GiB available of 926 (65% used). The disk is fine.

The stderr is discarded (`2>/dev/null`), both `df` calls print nothing, `disk_gb=0`, and the 40 GiB floor gate rejects the runner.
Hermes retries 6 times per slot and then posts the skip, without the preflight reason (`bin/k3dm-hermes:438` discards the output).

## Fix (for triage)

1. Probe portably: `/bin/df -k` (absolute macOS path) or POSIX `df -Pk`, converting KiB to GiB, so the result does not depend on PATH.
2. Distinguish "probe failed" from "0 GiB free": emit `disk_gb=` empty (or `disk_probe=failed`) and have `_e2e_remote_eval_gates`
   report `status=probe_failed reason=cannot read free disk on runner` instead of a capacity error.
3. Include the preflight `reason=` line in the Hermes skip message (`bin/k3dm-hermes:438-445`) so the next failure names itself.

Test: a BATS case that runs the probe script with a stub `df` that rejects `-g` (GNU behaviour, from the capture above) on PATH first,
and asserts the disk value still comes from the real filesystem (or that the gate reports probe failure, not capacity); positive
control with a BSD-style stub.
