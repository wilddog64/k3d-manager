# Bug: a nightly test run whose metrics push fails is lost without any alert

**Status:** FIXED
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Medium. A red nightly suite went unreported for a full day.
**Files:** `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`,
`scripts/tests/plugins/observability_k3dm_tests_rules.bats`, `docs/guides/grafana-dashboards.md`,
`CHANGELOG.md`

Related: `docs/bugs/2026-10-05-offline-tests-rotted-on-v1-41-0.md` (the failures this hid), and
`docs/bugs/2026-06-09-pushgateway-deployment-metrics-gap.md` (the same silence for deployment
metrics, fixed with `DeploymentMetricsStale`).

## Symptom

The 2026-10-04 nightly run found 2 failing cases. `~/Library/Logs/k3dm-test-metrics.log`:

```
[k3dm-test-metrics] 1622 cases, 2 failed
[k3dm-test-metrics] push attempt 1/3 failed: <urlopen error [Errno 61] Connection refused> — retrying
[k3dm-test-metrics] push attempt 2/3 failed: <urlopen error [Errno 61] Connection refused> — retrying
[k3dm-test-metrics] metrics push skipped (non-fatal): <urlopen error [Errno 61] Connection refused>
```

On `ubuntu-hostinger`, `k3dm_test_cases_failed` stayed `0` and `k3dm_test_cases_total` stayed
`2207` from 10-03 05:34 until the 10-05 run. No alert fired. The red suite became visible only
because the next night's push succeeded.

## Root cause

The push is non-fatal by design, and that part is correct: a Pushgateway outage must not fail
the test run. But Pushgateway keeps the last pushed value indefinitely, so a missed push looks
exactly like a current, healthy one. The only staleness rule, `OfflineSuiteStale`, keys on
`k3dm_test_last_success_timestamp_seconds` with a 7-day window. That catches "no green run in a
week" but not "last night's run never arrived". `k3dm_test_last_timestamp_seconds` is pushed on
every run, pass or fail, but no rule reads it.

The port-forward was down on 10-04 because of the launchd label hijack fixed in `4547e696`. This
spec does not fix that outage. It makes the next one visible.

## Fix spec

### File 1 — `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`

Add a rule directly after the `OfflineSuiteStale` rule (before `DeploymentMetricsStale`), at the
same indentation:

```yaml
        - alert: OfflineSuiteRunMissed
          expr: time() - k3dm_test_last_timestamp_seconds > 93600
          for: 1h
          labels:
            group: k3dm-tests
            severity: warning
          annotations:
            summary: "no offline test run recorded in >26h"
            description: "The nightly make test-metrics pushes k3dm_test_last_timestamp_seconds on every run, pass or fail. Pushgateway retains the last value, so a failed push looks like a current result; on 2026-10-04 a run with 2 failing cases was lost this way. Check ~/Library/Logs/k3dm-test-metrics.log for 'metrics push skipped' and the Pushgateway port-forward on localhost:9091."
```

### File 2 — `scripts/tests/plugins/observability_k3dm_tests_rules.bats`

1. Add `OfflineSuiteRunMissed` to the loop in `all five k3dm test-suite alerts are present`, and
   rename that test to `all six k3dm test-suite alerts are present`.
2. In `every k3dm alert carries a non-empty expr`, change `len(alerts) == 5` / `expected 5` to
   `6`, and `*"OK 5"*` to `*"OK 6"*`.
3. Add:

```bash
@test "OfflineSuiteRunMissed keys on the per-run timestamp, not the last success" {
  run python3 - "${ACG_RULE}" <<'PY'
import sys, re
text = open(sys.argv[1]).read()
m = re.search(r"- alert: OfflineSuiteRunMissed\n\s+expr: (.+)", text)
assert m, "OfflineSuiteRunMissed missing"
expr = m.group(1)
assert "k3dm_test_last_timestamp_seconds" in expr, expr
assert "last_success" not in expr, expr
window = int(re.search(r">\s*(\d+)", expr).group(1))
assert 86400 < window < 172800, window
print("OK")
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK"* ]]
}
```

### File 3 — docs

- In `docs/guides/grafana-dashboards.md`, change "The five `k3dm-tests.alerts` rules" to "The six
  `k3dm-tests.alerts` rules". Then add one sentence after that paragraph: `OfflineSuiteRunMissed`
  fires when no run, pass or fail, has been pushed for 26h, which is the signature of a failed
  push.
- `CHANGELOG.md` `[Unreleased]` → `### Fixed`: a prose entry.
- This file: flip **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: the new test and the two count assertions are RED at `HEAD` (paste output).
- [ ] Mutation: change the new expr to `k3dm_test_last_success_timestamp_seconds`; the new test
      goes red. Restore from a `$TMPDIR` snapshot and prove it with `cmp`.
- [ ] `bats scripts/tests/plugins/observability_k3dm_tests_rules.bats` is green; paste the counts.
- [ ] `python3 -c 'import yaml,sys;yaml.safe_load(open(sys.argv[1]))' scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`
      exits 0.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT make the push fatal or change `bin/k3dm-test-metrics`.
- Do NOT change the existing five rules' expressions or windows.
- Do NOT apply the rule to any cluster. The operator runs `make observability-acg`.
- Do NOT touch files outside those listed. No commit, push, PR or `--no-verify`.
