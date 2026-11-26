# Bug: GNU df fix tests do not cover the 200-character reason cap or the `$HOME` disk fallback

**Status:** OPEN — capture
**Priority:** P3 (test-only; the landed code is correct, two behaviours have no test)
**Introduced by:** `7bd1a7c4` (v1460-gnudf)
**Should have been caught by:** review
**Introducing change reviewed:** yes (Fable)
**Waiting on:** operator decision
**Prior art:** `docs/bugs/2026-11-25-e2e-m2-preflight-reads-0gib-disk-under-gnu-df.md` (parent, same change) — follow-up
**Filed:** 2026-11-25
**Detected by:** Neon blind post-land review, confirmed by Claude with mutants

## Observed

On `7bd1a7c4` both mutants pass every test (`bats scripts/tests/plugins/e2e_remote.bats`,
`python3 -m pytest scripts/tests/bin/test_hermes_e2e_text.py -q`):

1. Drop `[:200]` in `_e2e_preflight_reason` (`bin/k3dm-hermes`). The hostile-reason case
   (`scripts/tests/bin/test_hermes_e2e_text.py:91`) puts `\r\n` right after `@here`, so `.splitlines()` ends the
   `reason=` line there and the 500-character tail never reaches the cap (G-M3 "at most 200" is unproven).
2. Replace the `$HOME` fallback line in `_e2e_remote_probe` (`scripts/plugins/e2e_remote.sh`) with `:`. The probe test's
   `df` stub answers every path the same way, so the fallback is never needed.

## Fix direction

Tests only: a reason line longer than 200 allowed characters on one line asserts `len(record["reason"]) == 200`; a `df`
stub that fails for the report dir and answers for `$HOME` asserts `disk_gb=307`. Each red with its mutant applied.
