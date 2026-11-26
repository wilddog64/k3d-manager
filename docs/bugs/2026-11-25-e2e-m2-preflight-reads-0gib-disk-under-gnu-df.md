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
**Intent approved:** operator, 2026-11-25
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

## Spec (rev 2 — Fable blind review applied, see Review log)

**Files:** `scripts/plugins/e2e_remote.sh`, `scripts/tests/plugins/e2e_remote.bats`, `bin/k3dm-hermes`,
`scripts/tests/bin/test_hermes_e2e_text.py`, `docs/guides/vcluster-e2e-harness.md` (the status list at `:451-454` only). Nothing else.
Do not change M2 or any dotfile.

1. **Probe** (`_e2e_remote_probe`, `scripts/plugins/e2e_remote.sh:189-191`; the body is a heredoc sent over SSH, so keep `\$`
   escaping): measure with `df -Pk <dir>` and take the **third-from-last field of line 2** (`$(NF-2)`, available KiB; robust to a
   filesystem name with spaces such as `map auto_home`); print `disk_gb=<int(KiB / 1048576)>`. Keep the report-dir-then-`$HOME`
   fallback. If neither call yields a non-negative integer, print `disk_gb=` (empty) — never `0`.
2. **Gate** (`_e2e_remote_eval_gates`): insert immediately before the disk floor check at `:227`, after the docker, lock, CPU and
   memory gates (their precedence and tests are unchanged): if `disk` is empty or not `^[0-9]+$`, print
   `reason=cannot read free disk on runner ${E2E_M2_SSH_HOST}` then `status=probe_failed`, return 1. A numeric value below the floor
   still gives `status=capacity_disk`. `_e2e_remote_preflight_with_retry` (`:256`) is unchanged; because `probe_failed` is not
   `capacity_*` it is not retried there.
3. **Hermes** (`_run_e2e`, `bin/k3dm-hermes:438-445`): keep the preflight output (`_e2e_run` returns stdout + stderr, `:378`). The
   reason is the text after `reason=` on the first line that **starts** with `reason=`. Sanitise it: replace every character outside
   `[A-Za-z0-9 .,:%/()_-]` with `?` (this removes Slack mrkdwn such as `<!channel>`, `<https://x|y>`, `@`, `&`, backticks, and all
   control characters), then cut to 200 characters. Post `Hermes e2e <slot>: skipped — M2 runner unavailable after 6 attempts
   (<reason>)`; with no `reason=` line, post the current text exactly. Add `"reason": <sanitised>` to the slot record
   (`{"outcome": "runner-unavailable", "reason": ...}`); omit the key when there is no reason. The manual slot uses the same rule.
   **Hermes's own retry is unchanged (accepted):** any non-zero preflight, including `probe_failed`, is retried up to 6 times 30
   minutes apart (`:439-442`); this fix only makes the final message name the cause.
4. **Guide** (`docs/guides/vcluster-e2e-harness.md:451-454`): add `probe_failed` (free disk could not be read; not retried) to the
   status list.

## Files

- `scripts/plugins/e2e_remote.sh`
- `scripts/tests/plugins/e2e_remote.bats`
- `bin/k3dm-hermes`
- `scripts/tests/bin/test_hermes_e2e_text.py`
- `docs/guides/vcluster-e2e-harness.md`

## Contract readers

Found by grep on `k3d-manager-v1.46.0`, 2026-11-25 (Fable review):

| Reader | File:line | Effect of `probe_failed` / `"reason"` |
|---|---|---|
| Capacity retry | `scripts/plugins/e2e_remote.sh:256` | not retried (not `capacity_*`) |
| Dispatch refusal text | `scripts/plugins/e2e_remote.sh:460-461` | prints the reason as today |
| `e2e_runner_health` | `scripts/plugins/e2e_remote.sh:1062-1079` | non-`available` → warning, critical when a run is requested (same as other refusals) |
| Bootstrap / status pass-through | `scripts/plugins/e2e_remote.sh:332,342`, `Makefile:2311` | passes the status through |
| Hermes | `bin/k3dm-hermes:438-445` | uses return code; message gains the reason (item 3) |
| Slot record | `scripts/lib/hermes/e2e_schedule.py:46` (existence), `bin/k3dm-hermes:405` (reads `groups`) | new `reason` key ignored |
| Guide | `docs/guides/vcluster-e2e-harness.md:451-454` | lists the new status (item 4) |

**Proof of `df -Pk` (read-only, 2026-11-25):** on M2 with the runner's PATH (`/opt/homebrew/bin:/usr/local/bin:$PATH`, resolving
`gnubin/df`, GNU coreutils 9.12): header `Filesystem 1024-blocks Used Available Capacity Mounted on`, line 2 column 4 = 322088920 KiB
→ 307 GiB; `/bin/df -Pk` (BSD) on M2 → 307 GiB; `/bin/df -Pk` on M4 prints the same header columns.

**Tests:**

- **Probe** (`e2e_remote.bats`): run the real `_e2e_remote_probe` with `_e2e_remote_ssh() { PATH="$STUB:$PATH" bash -s; }` (stdin
  carries the script). Set `E2E_M2_LOCK` and `E2E_M2_REMOTE_REPORT_DIR` to `$BATS_TEST_TMPDIR` paths first. `$STUB` holds `docker`
  (exit 0), `top` (prints six `CPU usage: ... 90.0% idle` lines at once), `memory_pressure` (prints `free percentage: 80%`), and `df`.
  GNU-style `df` (from the M2 capture above): any `-g` argument → prints `df: invalid option -- 'g'` to stderr, exit 1; `-Pk` → the
  captured header and a line 2 with 322088920 available KiB. Assert the output has the exact line `disk_gb=307` (`grep -qx`). First,
  as a fixture check, run `PATH="$STUB:$PATH" bash -c 'command -v df'` and assert it prints `$STUB/df`. Second `df` stub fails for every call → exact line `disk_gb=` (`grep -qx 'disk_gb='`).
- **Gate:** blobs with good docker/lock/CPU/memory and `disk_gb=` or `disk_gb=abc` → `status=probe_failed` and the reason; positive
  controls: `disk_gb=10` → `capacity_disk` (existing test), `disk_gb=900` → `available`.
- **End-to-end no-retry:** stub only `_e2e_remote_probe` (healthy blob, `disk_gb=`), stub `sleep`, count probe calls through the
  real `e2e_runner_preflight` and `_e2e_remote_preflight_with_retry` with `E2E_M2_CAPACITY_RETRY_INTERVAL=0`: exactly 1 call and
  `status=probe_failed`. (Pre-fix: `capacity_disk` and 3 calls.)
- **Hermes** (`test_hermes_e2e_text.py`, reuse the scratch-HOME fixture of `test_run_e2e_records_null_counts_and_posts_once`):
  pre-write `<K3DM_HERMES_E2E_DIR>/slot.claim` with `{"attempts": 5}`; preflight returns
  `(1, "noise\nreason=disk free 0GiB below floor 40GiB\nstatus=capacity_disk\n")` → one post ending
  `(disk free 0GiB below floor 40GiB)`, record `{"outcome": "runner-unavailable", "reason": "disk free 0GiB below floor 40GiB"}`,
  claim file removed. No `reason=` line → post exactly the current text, no `reason` key. Hostile reason
  `reason=<!channel> <https://x|y> @here` plus `\r`, `\x1b[31m`, a tab and 500 characters → the post contains none of `<`, `>`,
  `|`, `@`, `\r`, `\x1b`, tab, and at most 200 reason characters.

## Acceptance

```yaml
must:
  - id: G-M1
    text: "With GNU df first on the runner PATH, the probe reports the real free disk in GiB"
  - id: G-M2
    text: "When free disk cannot be read, preflight reports status=probe_failed with a reason, not capacity_disk, after one probe"
  - id: G-M3
    text: "The Hermes skip message and slot record carry the preflight reason, sanitised to [A-Za-z0-9 .,:%/()_-] and at most 200 characters"
must_not:
  - id: G-N1
    text: "A failed disk measurement is reported as disk_gb=0 or gives capacity_disk"
  - id: G-N2
    text: "Runner-supplied text reaches Slack with mrkdwn or control characters"
evidence:
  - id: E-G-offline
    proves: [G-M1, G-M2, G-M3, G-N1, G-N2]
    kind: offline
    command: "bats scripts/tests/plugins/e2e_remote.bats and python3 -m pytest scripts/tests/bin/test_hermes_e2e_text.py -q pass; on the base commit plus only the new tests, the GNU-df probe test (disk_gb=0), the empty-disk tests, the end-to-end no-retry test (3 calls, capacity_disk) and the Hermes reason and hostile-reason tests fail; existing capacity_disk and available tests are positive controls; mutants, each reverted: (1) restore df -g -> GNU-df test fails; (2) fall back to disk_gb=0 -> exact-line empty test fails; (3) gate emits capacity_probe instead of probe_failed -> end-to-end no-retry test fails (3 calls); (4) strip only control characters in Hermes -> hostile-reason test fails"
    intent: "The daily e2e on M2 runs again when M2 has disk space, and if the check ever cannot measure something, Slack says exactly what instead of a misleading skip."
  - id: E-G-live
    proves: [G-M1]
    kind: live
    command: "Claude, read-only from M4 after landing: ./scripts/k3d-manager e2e_runner_preflight m2 status is neither capacity_disk nor probe_failed (if available, disk_gb is about 307); then the next Hermes e2e slot posts a PASS/FAIL result, not a skip (requires hub promote)"
    intent: "You see tomorrow's e2e result in Slack instead of 'skipped'."
interface:
  - "scripts/plugins/e2e_remote.sh: e2e_runner_preflight status=probe_failed"
  - "Hermes e2e skip message and slot record reason"
```

## Review log

| Rev | Reviewer | Verdict | Applied |
|---|---|---|---|
| 1 (`6134933a`) | Fable (blind, 2026-11-25) | NOT READY — 12 findings, all verified by Claude | rev 2: end-to-end no-retry test (mutant 3 did not bite), Slack allowlist sanitising, exact-line asserts, concrete probe harness (stub docker/top/memory_pressure, tmp lock and report dir), no newline-in-reason test, Hermes retry stated as accepted, contract readers + guide, gate placement, claim pre-write, live wording, `$(NF-2)` and non-multiple stub value |

## Original fix notes (capture)


1. Probe portably: `/bin/df -k` (absolute macOS path) or POSIX `df -Pk`, converting KiB to GiB, so the result does not depend on PATH.
2. Distinguish "probe failed" from "0 GiB free": emit `disk_gb=` empty (or `disk_probe=failed`) and have `_e2e_remote_eval_gates`
   report `status=probe_failed reason=cannot read free disk on runner` instead of a capacity error.
3. Include the preflight `reason=` line in the Hermes skip message (`bin/k3dm-hermes:438-445`) so the next failure names itself.

Test: a BATS case that runs the probe script with a stub `df` that rejects `-g` (GNU behaviour, from the capture above) on PATH first,
and asserts the disk value still comes from the real filesystem (or that the gate reports probe failure, not capacity); positive
control with a BSD-style stub.
