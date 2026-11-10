# Bug: nightly test-all stops at the first red stage, and the Tests dashboard shows the partial count as the total

**Status:** OPEN — filed 2026-11-09; Part A dispatched to Gemini 3.8 Flash 2026-11-09; Part B folded into
`docs/plans/v1.44.0-parallel-offline-tests.md` (operator, 2026-11-09)
**Priority:** P3
**Waiting on:** fix running — since 2026-11-09
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
**Intent approved:** operator, 2026-11-09
**Intent approval words:** "approve E1 and E2 and dispatch to Flash 3.8"; "let's fold Part B into v1.44.0 parallel plan"
**Dispatch:** operator go 2026-11-09, Part A only, `--agent agy --model gemini-3.8-flash-medium`
**Filed:** 2026-11-09
**Detected by:** operator, 2026-11-09, reading the k3dm Tests "Total cases" panel ("looks like that our test cases
increase") — Claude traced it
**Release:** P3 batch item on `k3d-manager-v1.43.15`, dashboard only. Part B ships with
`docs/plans/v1.44.0-parallel-offline-tests.md` Part B

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

### Part A — dashboard (no behaviour change; dispatched)

File: `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml` only.

- New `stat` panel "Run complete", query `k3dm_test_run_complete{target="test-all"}` (instant), placed in row y 26 next
  to "Total cases". `fieldConfig.defaults.mappings`:
  `[{"type": "value", "options": {"0": {"text": "stopped early", "color": "red"}, "1": {"text": "complete", "color": "green"}}}]`,
  `"noValue": "no data"`. Its description: a run that stops at a red stage counts only the stages that ran, see
  `OfflineSuiteRunIncomplete`. Re-flow the `gridPos` of panels in that row so none overlap; give it an unused `id`.
- "Total cases" and "Failed cases" keep their queries. Each description adds that a partial run (Run complete = stopped
  early) counts only the stages that ran.
- No overrides, hidden queries or transformations: only the stat-plus-value-mapping construct already deployed.
- **Failure tables (operator, 2026-11-09, added to this dispatch as a correction):** in "Failures in selected time
  range" (id 8) and "Failing test cases (latest run)" (id 4), drop the "Target / origin" (`instance`) and "Target"
  (`target`) columns (add both to `excludeByName`). Columns, in order: "Test case" (`case`, renamed from "Case"),
  "Test name", "Failure reason", then "Test suite". Today every publisher sends `target=test-all` and origin `local`
  (`Makefile:1581`, `bin/k3dm-webhook:1815`; no caller passes `--origin ci`), so both columns repeat one value on
  every row. If a second target or origin ever publishes, add the column back. Test suite stays because a case number
  is only unique within its suite.

**External behaviour proof (CLAUDE.md, 2026-11-07):** the hub runs kube-prometheus-stack `67.9.0`
(`scripts/etc/argocd/applicationsets/observability.yaml:18`, Grafana 11.4.0). The same construct, a `stat` panel with
`{"type": "value", "options": {"0": {"text": "down", "color": "red"}, "1": {"text": "up", "color": "green"}}}`, is
deployed on that Grafana in `scripts/etc/argocd/platform-ops/grafana-dashboard-host-cni-ipam.yaml:26` (since
`32393e17`, 2026-10-29). Claude, 2026-11-09, from the M4 (no hub kube context there); E2 is the live confirmation.
Deploy path: `scripts/etc/argocd/applicationsets/grafana-dashboards-hub.yaml:38` includes this file, so it reaches the hub
only after `make hub-promote`.

### Part B — run every stage: moved

Folded into `docs/plans/v1.44.0-parallel-offline-tests.md` Part B (operator, 2026-11-09), with its contract readers and
acceptance items. Not part of this dispatch.

## Files

| File | Change |
|---|---|
| `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml` | "Run complete" stat panel; two descriptions |
| `scripts/tests/bin/test_k3dm_tests_dashboard.py` | new pytest (E1, E3) |
| `scripts/tests/plugins/grafana_dashboard_appsets.bats` | update the panel 8 assertions at lines 265-266 (they pin "Target / origin", "Case" and a kept `instance`) |

## Contract readers

| Reader | Part A |
|---|---|
| `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml` | Changes: new panel, two descriptions |
| `scripts/etc/argocd/applicationsets/grafana-dashboards-hub.yaml:38` (includes the file) | No change: same file name |
| `scripts/etc/argocd/applicationsets/grafana-dashboards-acg.yaml:35` (excludes the file) | No change |
| `scripts/tests/plugins/grafana_dashboard_appsets.bats` (reads the file name) | No change; must still pass |
| `Makefile:1478` `VALIDATE_MANIFESTS_DEFAULT` (validates the YAML) | No change; must still pass |
| `bin/k3dm-test-metrics:203-208` (producer of `k3dm_test_run_complete`) | No change: metric name and label unchanged |

## Acceptance

```yaml
must:
  - id: M1
    text: "The k3dm Tests dashboard shows whether the latest test-all run completed every stage, next to Total cases."
  - id: M2
    text: "Both failure tables show Test case, Test name, Failure reason, Test suite, in that order."
must_not:
  - id: N1
    text: "A run that stopped early is never shown on the dashboard without a visible 'stopped early' state."
  - id: N2
    text: "Neither failure table shows a Target or Target / origin column."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "The dashboard's JSON has a run-complete panel on the right metric, and a test fails if the panel or its 'stopped early' mapping is removed."}
  - {id: E2, proves: [M1, N1], kind: live, intent: "After a promote, you open the k3dm Tests dashboard and see 'stopped early' for the current nightly run, which is partial."}
  - {id: E3, proves: [M2, N2], kind: offline, intent: "The dashboard JSON for both failure tables lists Test case, Test name, Failure reason, Test suite in that order and hides target and instance; a test fails if either column comes back or the order changes. Operator's request 2026-11-09."}
interface:
  - "scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml (ConfigMap; dashboard JSON under data)"
```

## Worker definition of done

- New test file `scripts/tests/bin/test_k3dm_tests_dashboard.py` (pytest): loads the ConfigMap YAML, parses the
  dashboard JSON, asserts the "Run complete" stat panel queries `k3dm_test_run_complete`, maps `0` to "stopped early"
  and `1` to "complete", and that no two panels' `gridPos` overlap. The fixture first asserts it read the repo's file
  (resolved from the test file's own path, not the cwd).
- Mutants shown red: (a) delete the panel, (b) delete the `0` mapping, (c) change the expr to another metric. Paste
  each red run.
- Run: `python3 -m pytest scripts/tests/bin/test_k3dm_tests_dashboard.py -q`,
  `bats scripts/tests/plugins/grafana_dashboard_appsets.bats`, and `make validate-manifests` if present. Paste each
  command, rc and the proving lines.
- `git diff --stat` touches only the dashboard file and the new test file. Leave the changes uncommitted; Claude
  reviews and lands. Do not run `make test-all`, kubectl, or anything against the hub; E2 is live, for the operator.
