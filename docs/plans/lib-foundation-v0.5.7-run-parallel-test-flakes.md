# Plan: `run_parallel.bats` — whole-second timing flake and a collision test that hides which file is missing (v0.5.7)

**Filed:** 2026-11-18
**Branch:** `release/v0.5.7`
**Status:** PLANNED — ready for dispatch
**Covers:** `docs/bugs/2026-11-14-lib-foundation-run-parallel-collision-test-flakes-on-linux.md`
(Investigation 2026-11-18)
**Risk:** low (test file only; no library change)
**Reviewed:** Claude only (P2 carry, test-only)
**Agent:** Luna (Codex)

## Problem

1. **Test "summary has sorted result lines followed by slowest and total"** (`scripts/tests/lib/run_parallel.bats:81-90`)
   asserts `^FAIL fail-item 0s \(rc 7\)$` (`:88`). `_run_parallel_worker` times a job as the difference of two
   whole-second `date +%s` readings (`scripts/lib/system.sh:878-882`), so a job of a few milliseconds that straddles a
   second boundary reports `1s`. Claude reproduced it 10/150 runs (ubuntu 24.04 amd64 under emulation, bats 1.13.0,
   2026-11-18). The `SLOWEST` and `TOTAL` checks in the same test already accept `[0-9]+s`.
2. **Test "bounds concurrency and records each result; sanitized collisions keep separate files"** (`:48-56`) failed
   once on Linux CI (run 43594861512, attempt 1: `a_b-2.rc` missing, five results for six items) and has not been
   reproduced in 850 runs. Its loop `[ -f log ] && [ -f rc ] && [ -f sec ]` (`:51-53`) cannot fail on any element
   except the last (an `&&` list does not trip errexit before its last element), never checks `.item`, and prints
   nothing about the out directory, so the next red will not say what was missing.

## Before You Start

1. Read `scripts/tests/lib/run_parallel.bats` in full and `scripts/lib/system.sh:866-975` (`_run_parallel_worker`,
   `_run_parallel`).
2. Run `bats scripts/tests/lib/run_parallel.bats` once and confirm it is green before editing.

## Fix (test file only)

1. **`:88`:** change the regex to `'^FAIL fail-item [0-9]+s \(rc 7\)$'`. Keep every other line of that test.
2. **`:51-53`:** replace the loop body so each of `log`, `rc`, `sec`, `item` is checked for each key, and the first
   missing file fails the test after printing diagnostics:

   ```bash
   for key in sleep_a sleep_b sleep_c sleep_d a_b a_b-2; do
     for ext in log rc sec item; do
       if [ ! -f "$RP_ROOT/out/$key.$ext" ]; then
         echo "missing: $key.$ext"
         ls -la "$RP_ROOT/out"
         for f in "$RP_ROOT/out"/*.item; do [ -e "$f" ] && printf '%s -> %s\n' "${f##*/}" "$(cat "$f")"; done
         return 1
       fi
     done
   done
   ```

   Keep `assert_max_overlap` (`:50`) and the two `.rc` checks (`:54-55`) as they are.

## Files

| File | Change |
|---|---|
| `scripts/tests/lib/run_parallel.bats` | Fix 1-2 |

## Contract readers

None: no library code, no output format, no shared path changes. `scripts/lib/system.sh` is read only.

## Proof (record each in the report)

- **P1 (Fix 1, pre-fix red):** create a scratch directory with an executable `date` shim that prints `100` on its first
  call in a test and `101` on every later call (state in a file under `$BATS_TEST_TMPDIR`; pass `+%s` through only),
  put it first on `PATH` for that one test run, and run the test by name. Old regex: red. New regex: green, and the
  summary line is `FAIL fail-item 1s (rc 7)`. Remove the shim afterwards; do not commit it.
- **P2 (Fix 2, pre-fix red):** temporarily edit `_run_parallel_worker` so it skips writing `.item` when
  `key == a_b-2` (apply, run, revert). Old test: green (it never checks `.item`). New test: red, printing
  `missing: a_b-2.item` and the directory listing. Repeat with the `.log` write skipped for `key == sleep_a`: old test
  green, new test red with `missing: sleep_a.log`. Revert `system.sh`; `git diff scripts/lib/system.sh` must be empty.
- **P3 (no regression):** `bats scripts/tests/lib/run_parallel.bats` green 20 times in a row on the unmodified library.

## What NOT to Do

- Do not change `scripts/lib/system.sh` or any other library or test file; the `.item`/`.log` edits in P2 and the
  `date` shim in P1 are temporary and must not appear in `git status` at the end.
- Do not loosen the other assertions in either test, add retries, or skip tests.
- Do not touch `CHANGELOG.md`, `README.md`, `docs/` or `memory-bank/`. Do not commit, push or open
  a PR; Claude verifies and commits.
- Do not skip hooks.

## Rules

LF only; keep indentation, quoting and naming; no unsolicited refactors. If the spec contradicts the code, stop and say so.

## Gates

`bats scripts/tests/lib/run_parallel.bats`, then `env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/lib/`, then
`shellcheck -x scripts/tests/lib/run_parallel.bats` if the repo already runs shellcheck on bats files (check the
Makefile/CI first; skip with a note if not).

## Definition of Done

- [ ] Fix 1-2; `git status` shows only `scripts/tests/lib/run_parallel.bats`.
- [ ] P1, P2 (both mutations) and P3 recorded with output.
- [ ] Gates green.
- [ ] Report: diff, proof output. No commit.

## Acceptance

```yaml
interface:
  - "scripts/tests/lib/run_parallel.bats (test names unchanged)"
must:
  - id: M1
    text: the summary test passes when a fast failing job's elapsed time rounds to 1s, and still checks the line's item, status and rc
  - id: M2
    text: the collision test checks log, rc, sec and item for every key and, on the first missing file, names it and lists the out directory and every item mapping
must_not:
  - id: N1
    text: the summary test fails because a job straddled a second boundary — red today (date shim, P1)
  - id: N2
    text: the collision test passes while a key's .item or a non-final key's .log is missing — red today (worker mutation, P2)
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    command: bats scripts/tests/lib/run_parallel.bats -f "summary has sorted|sanitized collisions"
    intent: "The parallel-runner tests stop failing by chance on slow CI machines, and if a result ever goes missing again the CI log names the missing file instead of a bare 'No such file'."
```

**Intent approved:** operator, 2026-11-18
**Approval words and scope:** "go ahead" (2026-11-18, after Claude proposed two test-only fixes upstream in
lib-foundation: accept `[0-9]+s` in test 4; per-key collision assertion with a directory dump). No library change.
