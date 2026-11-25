# e2e M2 preflight reads 0 GiB free disk when GNU `df` is first on PATH, so Hermes skips the daily e2e

**Status:** OPEN — captured 2026-11-25
**Priority:** P2 (daily Hermes e2e on M2 is skipped every slot; workaround: drop `gnubin` from M2's non-interactive PATH)
**Introduced by:** `62c9ff27` (v1.27.0, the `df -g` disk probe) meeting a `gnubin` entry in M2's `~/.zshenv` (date unknown)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-25
**Triage:** fix now in v1.46.0 (operator, 2026-11-25: "go ahead to have Fable review and dispatch to Luna")
**Branch:** `k3d-manager-v1.46.0`
**Implementer:** Luna (`--agent codex --model gpt-6-luna`)
**Intent approved:** pending
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

## Spec

**Files:** `scripts/plugins/e2e_remote.sh`, `scripts/tests/plugins/e2e_remote.bats`, `bin/k3dm-hermes`,
`scripts/tests/bin/test_hermes_e2e_text.py`. Nothing else. Do not change M2 or any dotfile.

1. **Probe** (`_e2e_remote_probe`, `:189-191`): measure with `df -Pk` (POSIX output; GNU and BSD `df` both accept `-P -k`), take
   column 4 of line 2 (available KiB) and print `disk_gb=<KiB / 1048576, integer, rounded down>`. Keep the report-dir-then-`$HOME`
   fallback. If neither call yields a non-negative integer, print `disk_gb=` (empty) — never `0`.
2. **Gate** (`_e2e_remote_eval_gates`): before the disk floor check, if `disk` is empty or not a non-negative integer, print
   `reason=cannot read free disk on runner ${E2E_M2_SSH_HOST}` / `status=probe_failed` and return 1. A real value below the floor
   still gives `status=capacity_disk`. `probe_failed` is not a `capacity_*` status, so `_e2e_remote_preflight_with_retry` does not
   retry it (unchanged code).
   The existing test "eval_gates treats missing metrics as a capacity stop, not available" must keep passing (its blob has a
   numeric `disk_gb`; only the CPU samples are missing).
3. **Hermes** (`_run_e2e`, `bin/k3dm-hermes:438-445`): keep the preflight output; on the final skip, take the value after the first
   `reason=` line, remove control characters, cut it to 200 characters, and post
   `Hermes e2e <slot>: skipped — M2 runner unavailable after 6 attempts (<reason>)`; with no `reason=` line, post the current text
   exactly. Write the same reason into the slot record as `"reason"`. The manual-slot path (`slot == "now"`, one attempt) uses the same
   wording rule. Nothing else in `_run_e2e` changes.

**Proof of `df -Pk` (read-only, 2026-11-25):** on M2 with the runner's PATH (`/opt/homebrew/bin:/usr/local/bin:$PATH`, resolving
`gnubin/df`, GNU coreutils 9.12): header `Filesystem 1024-blocks Used Available Capacity Mounted on`, line 2 column 4 = 322088920 KiB
→ 307 GiB; `/bin/df -Pk` (BSD) on M2 → 307 GiB; `/bin/df -Pk` on M4 prints the same header columns.

**Tests:**

- `e2e_remote.bats`: run the probe's script body locally (not over SSH) with a stub directory first on PATH holding a `df` that
  prints `df: invalid option -- 'g'` and exits 1 for any `-g` argument and otherwise prints POSIX `-Pk` output with 314572800
  available KiB (GNU behaviour from the 2026-11-25 M2 capture: GNU coreutils 9.12, `df -g` invalid, 308 GiB free); assert
  `disk_gb=300`. Second stub: `df` that fails for every call → `disk_gb=` empty. Assert first that the stub `df` is the one
  resolved (`command -v df`). Gate tests: `disk_gb=` and `disk_gb=abc` → `status=probe_failed`, not `capacity_disk`; `disk_gb=10`
  → `capacity_disk` (positive control); `disk_gb=900` with good CPU/mem → `available`. The retry test: a `probe_failed` verdict is
  called once, not retried.
- `test_hermes_e2e_text.py`: a runner whose preflight returns `(1, "reason=disk free 0GiB below floor 40GiB\nstatus=capacity_disk\n")`
  with the retry claim at 6 attempts → one post containing `(disk free 0GiB below floor 40GiB)` and a record with that `reason`;
  a preflight with no `reason=` line → the post is exactly the current text; a reason with a newline and 500 characters → one line,
  at most 200 characters of reason. Reuse the existing test's scratch-HOME fixture and its assertions.

## Acceptance

```yaml
must:
  - id: G-M1
    text: "With GNU df first on the runner PATH, the probe reports the real free disk in GiB"
  - id: G-M2
    text: "When free disk cannot be read, preflight reports status=probe_failed with a reason, not capacity_disk"
  - id: G-M3
    text: "The Hermes skip message and slot record carry the preflight reason, capped at 200 characters, one line"
must_not:
  - id: G-N1
    text: "A failed disk measurement is reported as 0 GiB or passes the gate as available"
  - id: G-N2
    text: "A real low-disk reading stops being capacity_disk, or probe_failed is retried as a capacity refusal"
evidence:
  - id: E-G-offline
    proves: [G-M1, G-M2, G-M3, G-N1, G-N2]
    kind: offline
    command: "bats scripts/tests/plugins/e2e_remote.bats and python3 -m pytest scripts/tests/bin/test_hermes_e2e_text.py -q pass; on the base commit plus only the new tests, the GNU-df probe test fails (disk_gb=0) and the probe_failed and Hermes-reason tests fail; mutants, each reverted: (1) restore df -g -> GNU-df test fails; (2) fall back to disk_gb=0 -> empty-value tests fail; (3) treat probe_failed as capacity_probe -> the no-retry test fails"
    intent: "The daily e2e on M2 runs again when M2 has disk space, and if the check ever cannot measure something, Slack says exactly what instead of a misleading skip."
  - id: E-G-live
    proves: [G-M1]
    kind: live
    command: "Claude, read-only from M4 after landing: ./scripts/k3d-manager e2e_runner_preflight m2 prints disk_gb near 308 and no capacity_disk; then the next Hermes e2e slot posts a PASS/FAIL result, not a skip (requires hub promote)"
    intent: "You see tomorrow's e2e result in Slack instead of 'skipped'."
interface:
  - "scripts/plugins/e2e_remote.sh: e2e_runner_preflight status=probe_failed"
  - "Hermes e2e skip message"
```

## Original fix notes (capture)


1. Probe portably: `/bin/df -k` (absolute macOS path) or POSIX `df -Pk`, converting KiB to GiB, so the result does not depend on PATH.
2. Distinguish "probe failed" from "0 GiB free": emit `disk_gb=` empty (or `disk_probe=failed`) and have `_e2e_remote_eval_gates`
   report `status=probe_failed reason=cannot read free disk on runner` instead of a capacity error.
3. Include the preflight `reason=` line in the Hermes skip message (`bin/k3dm-hermes:438-445`) so the next failure names itself.

Test: a BATS case that runs the probe script with a stub `df` that rejects `-g` (GNU behaviour, from the capture above) on PATH first,
and asserts the disk value still comes from the real filesystem (or that the gate reports probe failure, not capacity); positive
control with a BSD-style stub.
