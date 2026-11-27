# Bug: `make test-all` run by the hub webhook is killed at its 1800 s limit before finishing

**Status:** OPEN — filed, under review (Fable + Neon) before dispatch
**Priority:** P2
**Introduced by:** unknown (test suite growth against a fixed limit; last hub success 2026-11-14)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** investigation — since 2026-11-27 (spec review), then dispatch to Flash
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable on m4 (fell back to glob)
**Severity:** medium — every cloud `make-test-all` request fails (exit 124); the k3dm Tests dashboard goes stale;
v1.46.0 p3b's `--with-test-all` leg cannot pass. Local `make test-all` on a workstation is a workaround for the result,
not for the cloud path.
**Filed:** 2026-11-27, Claude, from the v1.46.0 p2b live check (operator: "go ahead to file those two P2 bugs")
**Component:** `scripts/lib/webhook/make_targets.py:37` (`"test-all": {"timeout": 1800}`); bridge watch timeout follows
it (`bin/k3dm-cloud-bridge` `_watch_entry` uses `MAKE_TARGETS[target]["timeout"]`)

## Evidence

- **Live, 2026-11-27, hub m5 on `deploy/hub` `54a13982`:** `bin/k3dm-cloud-request make-test-all --notify-route testing
  --wait-final --timeout 1800` from m4 → job `16aadbe5`, started 01:08:52Z. Final response
  `responses/20261127T010823Z-make-test-all.final.json`: `body.status` `failed`, `body.exit_code` 124, output tail ends
  `ok 757 E1 approval never pushes, …` then `make: *** [test-all] Terminated: 15`. Slack (operator screenshot, 17:38
  PST): "make test-all timed out after 1800s — job 16aadbe5".
- The BATS run reached test 757; m4's `make test` TAP plan is `1..2256` (p3a hand-back, 2026-11-26).
- **Grafana (Viewer token, 2026-11-27 01:48Z):** `k3dm_test_last_success_timestamp_seconds{instance="test-all-local-last-success"}`
  = 1794615110 (2026-11-14T00:11:50Z) — no hub `test-all` success in 13 days. `k3dm_test_suite_duration_seconds` has no
  series, so per-suite wall time is not recorded anywhere.
- Earlier cloud `make-test-all` finals on `cloud-requests`: 2026-10-07 and 2026-10-20 failed with exit 2 (test failures,
  not timeouts).

## What is not known (prove before choosing a limit)

- How long `make test-all` takes on m5 under the webhook (launchd environment, no TTY) versus interactively on m5 and
  on m4 (~15 min for `make test`, 442 s for `make test-pytest`, Luna 2026-11-26). If the hub is several times slower
  than m4, raising the limit hides a hub-side cause (throttling, a hung test waiting on a timeout, network fallbacks).
- Which suite or file consumes the time.

## Proposed fix (two parts; the reviewers should challenge the split)

1. **Measure:** make the `test-all` recipe print a wall-clock line per suite (`test`, `test-bin`, `test-python`) to
   the job log, and have `bin/k3dm-test-metrics` export them as `k3dm_test_suite_duration_seconds{suite=…}` (the gauge
   is declared but empty).
2. **Limit:** raise `make_targets.py` `test-all` timeout to 3600 s as a stopgap so a full run can finish and report
   the durations from part 1; the final limit is chosen from that measurement.

## Files

- `scripts/lib/webhook/make_targets.py`
- `Makefile` (`test-all` recipe only)
- `bin/k3dm-test-metrics`
- `scripts/tests/bin/test_k3dm_test_metrics.py`
- `scripts/tests/bin/test_webhook_make_targets.py` (or the existing make-targets test file)

## Contract readers

- `MAKE_TARGETS["test-all"]["timeout"]`: readers `scripts/lib/webhook/lifecycle.py` (`_run_make_target` kill timer),
  `bin/k3dm-cloud-bridge` `_watch_entry` (final-response watch), `docs/howto/cloud-session-requests.md` (states
  timeouts, if it does), `scripts/lib/acceptance/live.py` (p3b `make-test-all` leg deadline 1200 s — must be ≥ the new
  limit or the leg times out first).
- Metric `k3dm_test_suite_duration_seconds`: readers the k3dm Tests dashboard (if a panel uses it), alert rules (grep).

## Acceptance

```yaml
must:
  - id: T-M1
    text: "a test-all job log contains one wall-clock duration line per suite, and the exporter publishes k3dm_test_suite_duration_seconds for each suite"
  - id: T-M2
    text: "the hub test-all job and the bridge's final-response watch both allow 3600 s"
must_not:
  - id: T-N1
    text: "the webhook kills a test-all run before 3600 s"
    red_on_current: "red: MAKE_TARGETS['test-all']['timeout'] is 1800 on the current code; the test asserts 3600"
  - id: T-N2
    text: "a suite duration line or metric is missing when that suite ran"
    red_on_current: "red: the current recipe prints no durations and the gauge has no series"
  - id: T-N3
    text: "a consumer of the limit (bridge watch, p3b live leg deadline) still expires before the job limit"
    red_on_current: "red: live.py make-test-all leg deadline is 1200 s, below both the current and new limit"
evidence:
  - id: T-E1
    proves: [T-M1, T-M2, T-N1, T-N2, T-N3]
    kind: offline
    command: "python3 -m pytest on the touched test files passes; on the current code plus only the new tests, T-N1, T-N2 and T-N3 fail"
    intent: "A cloud test-all run gets enough time to finish, and every run records how long each part took."
  - id: T-E2
    proves: [T-M1, T-M2]
    kind: live
    command: "after a hub promote: bin/k3dm-cloud-request make-test-all --wait-final --timeout 3700 finishes with exit 0 or a real test failure (not 124); its job log shows the three suite durations; Grafana shows k3dm_test_suite_duration_seconds for the run"
    intent: "You can run the full test suite from a cloud session again, and see on the dashboard which suite is slow."
interface:
  - "MAKE_TARGETS['test-all']['timeout'] = 3600"
  - "k3dm_test_suite_duration_seconds{suite} populated"
```
