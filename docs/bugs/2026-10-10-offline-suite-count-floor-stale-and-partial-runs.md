# Bug: the offline-suite count floor is stale, and a partial `test-all` run reads as a dropped suite

**Filed:** 2026-10-10
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN — spec ready (v1.43.2 batch 1)
**Priority:** P3 — alert hygiene; no outage, but the alert can no longer catch what it exists for
**Severity:** low

## Symptom

`OfflineSuiteCaseCountDropped` fired on ubuntu-hostinger with "offline suite total is 1481, below
the expected floor". Hostinger Prometheus history for `k3dm_test_cases_total{target="test-all"}`:

| Push (UTC) | Total | Run |
|---|---|---|
| 2026-10-09 19:09 | 1423 | BATS printed `1..1423`, then `make[1]: *** [test] Error 1` (test tripwire); pytest and unittest never ran |
| 2026-10-09 20:04 | 2664 | full run |
| 2026-10-10 11:44 | 1481 | no log kept; the same shape (about the BATS count alone) |
| 2026-10-10 12:44 | 2847 | full run: 1914 BATS + 838 pytest + 95 unittest |

There are two defects.

1. **The floor is stale.** `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml` sets
   `k3dm_test_cases_total < 1500`, which was measured at 1692 on 2026-09-27. The full run is now 2847.
   If all of pytest (838) dropped out of collection, the total would be 2009, so the alert this rule
   exists for would not fire.
2. **A partial run looks like a dropped suite.** The `test-all` target chains
   `make test && make test-bin && make test-python`. When an earlier stage fails, the later stages
   never run, but `bin/k3dm-test-metrics` still pushes the total it parsed. The alert then reports
   "suites dropped out" when the real event is "the run stopped early". Nothing else flags a run that
   stopped early with zero failed cases: `OfflineSuiteFailing` needs a failed case, and the
   `failed_untriaged` classification has no alert.

## Cause

The floor is a hand-set constant that nothing keeps in step with the suite. The producer has no idea
which stages ran, so a count from a run that stopped early can't be told apart from a count from a
complete run.

## Fix

**Makefile `test-all`:** after each stage succeeds, print a marker line into the same pipe, so it
lands in the log:

```
[test-all] stage-complete test
[test-all] stage-complete test-bin
[test-all] stage-complete test-python
```

Pass `--expected-stages test,test-bin,test-python` to `bin/k3dm-test-metrics`.

**`bin/k3dm-test-metrics`:**
- Parse the `stage-complete` markers.
- When `--expected-stages` is given, emit `k3dm_test_run_complete{target="<target>"}`: `1` when
  every expected stage has a marker, otherwise `0`. Add `# HELP` and `# TYPE gauge` lines.
- Without the flag, emit no such series. Other targets keep their current behaviour.

**`scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`:**
- `OfflineSuiteCaseCountDropped` changes to
  `k3dm_test_cases_total < 2600 and on(target) k3dm_test_run_complete == 1`. 2600 is about 90% of
  the 2847 full run on 2026-10-10. Update the description to give the new measurement, and say the
  floor applies only to complete runs.
- New `OfflineSuiteRunIncomplete`: `k3dm_test_run_complete == 0`, `for: 30m`, severity `warning`,
  group `k3dm-tests`. The summary names the target. The description says a stage failed before the
  later suites ran, and points to the `[test-all] metrics log:` path printed by the run.

## Tests

- `scripts/tests/bin/test_k3dm_test_metrics.py`:
  - A log with all three markers and `--expected-stages` gives `k3dm_test_run_complete{...} 1`.
  - A log with only `test`'s marker gives `0`.
  - Without `--expected-stages`, the payload has no `k3dm_test_run_complete` line.
  - Tests must not push to a live Pushgateway: monkeypatch `push_metrics` as the existing tests do.
- `scripts/tests/plugins/observability_k3dm_tests_rules.bats`:
  - Asserts the floor is `2600` and the `on(target) k3dm_test_run_complete == 1` guard.
  - Asserts `OfflineSuiteRunIncomplete` exists with `== 0`.
  - Assert on meaningful tokens, never on a whole line.

Mutation checks (each must turn the named tests red):
- Always emit `1`: the partial-log test goes red.
- Drop the guard from the rule: the BATS guard assertion goes red.

## Rollout

The operator runs `make prometheus-rules` (Hostinger), then `make test-metrics` on the M4.
Afterwards, `k3dm_test_run_complete{target="test-all"}` reads `1` in Hostinger Prometheus.

## Files

- `Makefile`
- `bin/k3dm-test-metrics`
- `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`
- `scripts/tests/bin/test_k3dm_test_metrics.py`
- `scripts/tests/plugins/observability_k3dm_tests_rules.bats`
- `docs/guides/grafana-dashboards.md`: the k3dm Tests metrics table gains `k3dm_test_run_complete`
- `CHANGELOG.md`

Commit message: `fix(tests): count floor applies to complete runs only; alert on a run that stopped early`
