# Bug: two tests pass or fail by runner: `test_webhook_log.py` relies on a sibling's sys.path, `machine_secrets.bats` N5 scans every /tmp/k3dm-*

**Status:** LANDED 2026-11-15 — test-only fix by Claude (operator: "go with your recommendation")
**Priority:** P3
**Classified:** not run (fixed on the operator's E2 decision before triage)
**Introduced by:** pre-existing
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Prior art:** exact-slug glob, none; `make find-similar-docs` not run
**Waiting on:** live check

## Symptom

Plan 1 E2 (`docs/plans/v1.44.0-parallel-offline-tests.md`, "E2 live result"), M4, 2026-11-14, commit 234bc2d1:
serial and parallel `make test-all` ran the same 5602 cases but disagreed on two files.

1. `scripts/tests/bin/test_webhook_log.py`: passes serially, 3 failed in parallel with
   `ModuleNotFoundError: No module named 'webhook'`. It imports `webhook.log` without putting `scripts/lib` on `sys.path`; serially a
   sibling (`test_webhook_access_log.py` and others insert it at import) ran first in the same pytest process.
2. `scripts/tests/bin/machine_secrets.bats` N5: `not ok` serially, `ok` in parallel. Its leak scan grepped
   `"${TMPDIR:-/tmp}"/k3dm-*` for the sentinel `74657374`, which matched other bats runs' copies of `machine_secrets.bats` itself
   under `/tmp/k3dm-test-bin-scratch.*`. Parallel jobs get their own TMPDIR.

## Fix

- `test_webhook_log.py` inserts `ROOT/scripts/lib` into `sys.path`, as its siblings do.
- N5 runs the script with `TMPDIR="$TMP/script-tmp"` and scans only `$TMP`.

## Evidence (Claude, M4, 2026-11-15)

- `test_webhook_log.py` alone: pre-fix 3 failed, post-fix 3 passed.
- N5 with a stray `/tmp/k3dm-e2-n5-plant/stray` holding the sentinel: pre-fix `not ok`, post-fix `ok`.
- Positive control: `MACHINE_SECRETS_SOURCE` wrapper that writes the sentinel to `$TMPDIR/k3dm-leak` then runs the real script:
  post-fix N5 `not ok`, `leak: .../script-tmp/k3dm-leak`.
- Full `machine_secrets.bats`: 25/25 ok.
- Live: parallel and serial `make test-all` agree per file (plan 1 E2 rerun).
