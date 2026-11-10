# Bug: nightly test-all stops at the first red stage, and the Tests dashboard shows the partial count as the total

**Status:** OPEN — filed 2026-11-09; not scheduled (operator: "we don't need to dispatch right away")
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-09 (Part B changes what a run does; Part A needs only intent approval)
**Introduced by:** pre-existing. The `&&` chain predates `63d29a47` (v1.43.2), which kept it and added
`k3dm_test_run_complete` and `OfflineSuiteRunIncomplete` but no dashboard panel for them
**Should have been caught by:** spec (`docs/bugs/2026-10-10-offline-suite-count-floor-stale-and-partial-runs.md` added
the completeness signal to Prometheus and alerting but not to the dashboard people read)
**Prior art:** `docs/bugs/2026-10-10-offline-suite-count-floor-stale-and-partial-runs.md` (found by grep, not scored) —
read, same mechanism, different defect: that fix made a partial run detectable by alert and is LIVE-VERIFIED; this bug is
what it left visible on the dashboard and in coverage. Also read `docs/bugs/2026-11-02-hostinger-offline-suite-alerts.md`
and `docs/bugs/2026-11-06-machine-setup-leaves-nightly-suite-without-pyyaml.md`: same alert, environmental root cause,
different defect. `make find-similar-docs` unavailable (vector store unreachable from the M4: `context
"k3d-k3d-cluster" does not exist`, 2026-11-09).
**Severity:** low–medium — no outage. While `make test` is red, a new regression in `test-bin` or the Python suites
(about 55% of all cases) is invisible to the nightly run, and the dashboard reads as if the whole suite ran.
**Approval:** operator, 2026-11-09: "can you investigate this and file a proper bug if necessary. we don't need to
dispatch right away"
**Intent approved:** not yet
**Filed:** 2026-11-09
**Detected by:** operator, 2026-11-09, reading the k3dm Tests "Total cases" panel ("looks like that our test cases
increase") — Claude traced it
**Release:** unscheduled; groom at the next `/release-groom`. Part B overlaps `docs/plans/v1.44.0-parallel-offline-tests.md`
Part B (same `test-all` recipe)

## Symptom

The k3dm Tests dashboard "Total cases" panel (`k3dm_test_cases_total{target="test-all"}`) shows 1995 → 2012 → 2016 →
2025 between 2026-11-06 and 2026-11-09. The suite at HEAD has 3088 BATS cases and 1496 Python test functions (static
count, `git grep`, 2026-11-09), and the last complete run published 3052 (2026-10-16, per the 2026-10-10 bug).

The panel tracks only the first stage. `make test` covers the BATS files outside `scripts/tests/bin`: 2034 `@test`
cases at HEAD, against the panel's 2025. `test-bin` (1054 BATS cases) and `test-python` have not run in a nightly
`test-all` since the M5 cutover: the first M5 run reported "29 failed of 1995, `k3dm_test_run_complete 0`"
(`docs/bugs/2026-11-06-machine-setup-leaves-nightly-suite-without-pyyaml.md:18`).

The same on the M4 before the cutover, `~/Library/Logs/k3dm-test-metrics.log`, run of 2026-10-30 04:30: `make[2]: ***
[test] Error 1`, no `stage-complete` line, then `[k3dm-test-metrics] 1916 cases, 2 failed` and `metrics pushed:
test-all/local`.

## Root cause

1. `Makefile:1570-1577`: `test-all` runs `make test && … make test-bin && … make test-python`. A red stage stops the
   chain, so the later stages' cases are neither run nor counted. The 2026-10-10 fix kept this deliberately and made it
   detectable: `bin/k3dm-test-metrics:203-208` emits `k3dm_test_run_complete 0`, and
   `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml:40` fires `OfflineSuiteRunIncomplete`.
2. `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml` has no panel that reads `k3dm_test_run_complete`. "Total
   cases" and "Failed cases" show a partial run's numbers with nothing saying the run stopped early. The alert is the
   only signal, and it has fired continuously since the cutover for environmental reasons, so it reads as noise.

## Fix

### Part A — dashboard (no behaviour change)

- New stat panel "Run complete" on `k3dm_test_run_complete{target="test-all"}`: `1` → "complete" (green), `0` →
  "stopped early" (red), no data → "no data".
- "Total cases" and "Failed cases" keep their queries, and their descriptions say a partial run counts only the stages
  that ran. "Total cases" turns amber when `k3dm_test_run_complete == 0` (a second hidden query or override).
- Grafana version proof is required before dispatch (CLAUDE.md "Prove external behaviour"): the value mappings and
  overrides used must be captured from the hub's deployed Grafana.

### Part B — run every stage (operator decision)

Change `test-all` to run all three stages whatever each returns, and exit non-zero if any failed. Each stage prints
`[test-all] stage-complete <stage>` once it has **run**, pass or fail, so `k3dm_test_run_complete 0` then means a stage
aborted or was killed, not that it had a failing case. `OfflineSuiteFailing` still carries the failures.

- For: the nightly run counts and reports every case every night, and E3 of the v1.43.16 parent
  (`docs/bugs/2026-11-09-offline-test-all-red-on-m4-four-root-causes.md`) can compare full counts.
- Against: a red `make test` no longer saves the ~15 minutes of later stages, and the meaning of the `stage-complete`
  marker changes for every reader below.
- Claude's recommendation: do Part B inside `docs/plans/v1.44.0-parallel-offline-tests.md` Part B, which already
  rewrites this recipe, runs every file regardless of other failures, and keeps the markers. Then only the serial
  recipe's meaning needs deciding. Part A stands alone as a P3 batch item.

## Contract readers

| Reader | Part A | Part B |
|---|---|---|
| `bin/k3dm-test-metrics:52` (marker regex), `:203-208` (`run_complete`) | No change | No code change; meaning of `run_complete` changes (ran vs passed) |
| `scripts/tests/bin/test_k3dm_test_metrics.py:244-273` (marker fixtures) | No change | Add a case: failing stage still prints its marker |
| `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml:31` (`OfflineSuiteCaseCountDropped`, gated on complete runs) | No change | Fires on more runs, because more runs become complete; floor 2600 is below today's ~4600 |
| `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml:40` (`OfflineSuiteRunIncomplete`) | No change | Description changes: "a stage aborted", not "a stage failed" |
| `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml` | New panel, descriptions | No change |
| `scripts/tests/bin/test_test_tripwire.py` (asserts the `test-all` recipe wraps each stage) | No change | Must still pass with the new recipe |
| `scripts/lib/webhook/lifecycle.py:215`, `bin/k3dm-webhook:1815` (look for `metrics pushed:`) | No change | No change: the push line is kept |
| `docs/plans/v1.44.0-parallel-offline-tests.md` Part B item 3 (keeps markers) | No change | Must use the same marker meaning |

## Acceptance

```yaml
must:
  - id: M1
    text: "The k3dm Tests dashboard shows whether the latest test-all run completed every stage, next to Total cases."
  - id: M2
    text: "(Part B, if chosen) make test-all runs test, test-bin and test-python even when an earlier stage fails, and exits non-zero if any stage failed."
  - id: M3
    text: "(Part B, if chosen) each stage that ran prints its stage-complete marker, so a run with failing cases in all three stages publishes run_complete 1 and every stage's cases."
must_not:
  - id: N1
    text: "A run that stopped early is never shown on the dashboard without a visible 'stopped early' state."
  - id: N2
    text: "(Part B) a failing stage never makes test-all exit 0."
  - id: N3
    text: "(Part B) a stage killed or aborted before finishing never prints its marker (run_complete stays 0)."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "The dashboard's JSON has a run-complete panel on the right metric, and a test fails if the panel or its 'stopped early' mapping is removed."}
  - {id: E2, proves: [M1, N1], kind: live, intent: "After a promote, you open the k3dm Tests dashboard and see 'stopped early' for the current nightly run, which is partial."}
  - {id: E3, proves: [M2, M3, N2, N3], kind: offline, intent: "With fake stages that pass, fail or get killed, test-all runs every stage, exits red when any fails, and prints a marker only for stages that finished."}
interface:
  - "make test-all (stages stubbed via MAKE overrides)"
  - "bin/k3dm-test-metrics --expected-stages"
  - "scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml"
```

## Worker definition of done

- E1 (and E3 if Part B is chosen) pass; paste each command, rc and the proving lines; each must_not shown red by a mutant.
- The worker does not run the real `make test-all` or touch the hub; E2 is live, after a promote, for the operator.
