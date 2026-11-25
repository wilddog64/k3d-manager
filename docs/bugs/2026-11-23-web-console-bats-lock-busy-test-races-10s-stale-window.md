# web_console_totp.bats test 23: lock-busy check races the 10-second stale window

**Status:** OPEN — captured 2026-11-23, not triaged
**Priority:** P3 (test-only; intermittent; the installer behaves correctly)
**Triage:** backlog — pull into a release that already touches `scripts/tests/bin/web_console_totp.bats` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** v1.45.0 (`0c27b830`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23
**Prior art:** not run (find-similar-docs vector store unavailable on m4: kube context missing); slug ls found no match

## Symptom

During `land` of `totp-a1-fix-decay-and-rotate` on 2026-11-23 (m4-air), the fast gate failed:
`not ok 23 [M9] [N11] interpreter and file custody refusal controls`, `[ "$status" = 7 ]` at
`scripts/tests/bin/web_console_totp.bats:635`. The whole suite took 845 s while other agents ran on the host.
Test 23 alone then passed 5 of 5 on the fix and on the release branch. The worker and the independent verifier ran
the full suite earlier and both got 34/34.

## Cause

The test runs `mkdir "$root/var/db/k3dm-web-console.lock"` (no `holder` file) and expects `install` to refuse with
exit 7. `_wc_lock_live` (`scripts/lib/web_console_common.sh:449-451`) treats a lock with no holder as live only while
`now - mtime < 10`. If more than 10 s pass between the `mkdir` and the check, the lock counts as stale.
`_wc_reclaim` then removes it and install carries on, so it does not exit 7. Under host load that delay is reachable.

## Fix direction

Change the test only: write a `holder` file naming a live process and its `ps -o lstart=` start time (for example the
bats process itself), so the lock is live however slow the host is. Keep a positive control for the holder-less
stale-reclaim path with a lock whose mtime is set far in the past.
