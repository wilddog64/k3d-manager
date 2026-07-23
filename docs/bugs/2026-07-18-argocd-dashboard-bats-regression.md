# Bug: `argocd_metrics_servicemonitor.bats` 12/13 fail after the trivy split

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/tests/plugins/argocd_metrics_servicemonitor.bats` (ONLY)

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "argocd dashboard BATS regression" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/tests/plugins/argocd_metrics_servicemonitor.bats` (the file you are fixing)
  - `scripts/tests/plugins/trivy_operator_observability.bats` (the ALREADY-CORRECT model —
    it was retargeted the same way in `4c89dabb`; copy its `TRIVY_DASH` idiom exactly)
  - `scripts/etc/grafana/dashboards/trivy-security-configmap.yaml` (where the panels now live)
  - `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` (what stayed on the hub)
- Implement exactly what is written — no interpretation, no extra refactors.

---

## Problem

`4c89dabb` moved trivy panels `11,13,14,15,18` off the hub dashboard into the new
app-cluster dashboard. `trivy_operator_observability.bats` was retargeted as part of that
commit; **`argocd_metrics_servicemonitor.bats` was not** — it asserts the same panels
against `${DASH}` (the hub file) and now fails.

Verified 2026-07-18:

```
8714721b (before split):  1..15  all ok
3fa6e5ef (current):       13/15  — not ok 12, not ok 13
```

**Root cause:** the trivy split spec's gate list named only one BATS suite. A second suite
asserting the same panels was never searched for, so the regression shipped unnoticed and
was not caught in review.

**Secondary defect — a now-vacuous test.** Test 14 (`dashboard banner uses real newlines
not literal backslash-n`) greps `${DASH}` for `\\n`. The banner it was written to guard
moved to the app-cluster dashboard, so the test now passes by absence and protects
nothing. It must follow the banner.

---

## Fix

### Change 1 — add the `TRIVY_DASH` variable

**Exact old block (line 5):**

```bash
DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"
```

**Exact new block:**

```bash
DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"
TRIVY_DASH="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/trivy-security-configmap.yaml"
```

### Change 2 — test 12: retarget every assertion to `TRIVY_DASH`

In `@test "metrics: dashboard includes trivy infra security panels"`, **all nine** `run grep`
lines currently end in `"${DASH}"`. Change every one of them to `"${TRIVY_DASH}"`. Do not
change the grep patterns, the `-F` flags, or the status assertions — only the file variable.

Then append these two disappearance assertions inside the same test, at the end, proving the
panels really left the hub:

```bash
  run grep -F -- 'Trivy Infra High/Critical Findings' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy Cluster Compliance Failures' "${DASH}"
  [ "${status}" -ne 0 ]
```

### Change 3 — test 13: split positive and negative assertions

**Exact old block:**

```bash
@test "metrics: dashboard has exactly one trivy drilldown table and banner" {
  run grep -cF -- '### Trivy drilldown' "${DASH}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  run grep -F -- '"title": "Trivy Drilldown",' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy Infra RBAC Drilldown' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy ClusterRole Drilldown' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- '"url": "?viewPanel=16"' "${DASH}"
  [ "${status}" -ne 0 ]
}
```

**Exact new block:**

```bash
@test "metrics: dashboard has exactly one trivy drilldown table and banner" {
  run grep -cF -- '### Trivy drilldown' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  run grep -F -- '### Trivy drilldown' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- '"title": "Trivy Drilldown",' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy Infra RBAC Drilldown' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy ClusterRole Drilldown' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- '"url": "?viewPanel=16"' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]
}
```

### Change 4 — test 14: follow the banner to the new dashboard

**Exact old block:**

```bash
@test "metrics: dashboard banner uses real newlines not literal backslash-n" {
  run grep -F -- '\\n' "${DASH}"
  [ "${status}" -ne 0 ]
}
```

**Exact new block:**

```bash
@test "metrics: dashboard banner uses real newlines not literal backslash-n" {
  run grep -F -- '\\n' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- '\\n' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/tests/plugins/argocd_metrics_servicemonitor.bats` | retarget tests 12/13/14 to the split dashboards |

---

## Rules

- `bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats` → **`1..15`, all 15 ok**
- `bats scripts/tests/plugins/trivy_operator_observability.bats` → `1..6`, all ok (unchanged)
- `grep -c 'TRIVY_DASH' scripts/tests/plugins/argocd_metrics_servicemonitor.bats` → **`16`**
  (1 definition + 15 uses: 9 retargeted in test 12, 5 in test 13, 1 in test 14)
- `./scripts/k3d-manager _agent_audit` — exit 0
- **No file other than the one BATS file may be touched.** In particular: do NOT edit either
  dashboard YAML to make a test pass. The dashboards are correct; the tests are stale.

---

## Definition of Done

- [ ] `argocd_metrics_servicemonitor.bats` passes `15/15`
- [ ] `trivy_operator_observability.bats` still passes `6/6`
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] `_agent_audit` exit 0
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
test(observability): retarget argocd dashboard trivy assertions after split
```

---

## What NOT to Do

- Do NOT edit `grafana-dashboard-argocd.yaml` or `trivy-security-configmap.yaml` — the
  dashboards are correct, the assertions are stale. Changing a dashboard to satisfy a stale
  test would silently undo the trivy split.
- Do NOT delete tests 12, 13, or 14. Retarget them. A deleted test is not a passing test.
- Do NOT weaken an assertion to `[ true ]` or drop a grep pattern to make it pass.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the single listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Process Note (why this happened)

The trivy split spec listed one BATS suite in its gates. No search was done for other suites
asserting the same panels, so a second stale suite shipped undetected and the review that
followed reported "bats 1..6 all ok" — the named suite, not the affected ones.

**Rule going forward:** when a spec moves content between files, the gate list must be
derived from a grep across `scripts/tests/`, not from the one suite that comes to mind.
