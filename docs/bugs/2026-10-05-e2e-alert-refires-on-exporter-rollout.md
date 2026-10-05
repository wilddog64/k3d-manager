# Bug: `E2EVerificationFailing` re-fires on every exporter rollout and names the wrong service

**Status:** FIXED
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Low. The alert itself is correct, but it pages again for the same red run, and its
subject is misleading.
**Files:** `scripts/etc/argocd/platform-ops/prometheusrule.yaml`,
`scripts/tests/plugins/e2e_observability.bats`, `CHANGELOG.md`

## Symptom

The operator saw `[FIRING] E2EVerificationFailing on hub` twice for one failing run (Oct 4, and
again at 06:24 on Oct 5 with "2 alerts"). Hub Prometheus `ALERTS` history:

```
pod=vulnerability-inventory-exporter-5597dfdb5d-bqj4w   10-04 20:20 -> 10-05 05:16
pod=vulnerability-inventory-exporter-74b46f4d96-rndhf   10-05 05:26 -> now
```

The underlying gauge did not change. It is the same `run_id 1791168841-15959` (8 of 102 failed,
the order status enum; its fix is pending the e2e image rebuild). Only the exporter pod was
replaced.

The summary also reads "failing on vcluster for **vulnerability-inventory-exporter**".

## Root cause

1. **The series identity includes the scrape target.** `expr: e2e_last_run_pass == 0` keeps
   `pod` and `instance`. A new exporter pod produces a new series, so the old alert resolves and a
   new one goes pending, then fires 10 minutes later. Every exporter rollout re-sends the page.
2. **The `service` label collision.** The exporter emits `service="<service under test>"`, but
   Prometheus's target label `service` (the exporter's own Service) wins, and the exported value is
   kept as `exported_service`. The annotations read `$labels.service`, so they name the exporter.

`E2EVerificationStale` has both defects.

## Fix spec

### File 1 — `scripts/etc/argocd/platform-ops/prometheusrule.yaml`

Replace:

```yaml
          expr: e2e_last_run_pass == 0
```

with:

```yaml
          expr: max by (tier, exported_service, project, runner) (e2e_last_run_pass) == 0
```

Replace:

```yaml
          expr: time() - e2e_last_success_timestamp_seconds > 259200
```

with:

```yaml
          expr: time() - max by (tier, exported_service, project, runner) (e2e_last_success_timestamp_seconds) > 259200
```

In the `annotations` of **both** `E2EVerificationFailing` and `E2EVerificationStale`, replace every
`{{ $labels.service }}` with `{{ $labels.exported_service }}`. Change nothing else in those
annotations.

### File 2 — `scripts/tests/plugins/e2e_observability.bats`

Add:

```bash
@test "e2e alerts aggregate away the scrape target and name the exported service" {
  run python3 - "${RULE}" <<'PY'
import sys, yaml
r = list(yaml.safe_load_all(open(sys.argv[1])))[0]
groups = {g["name"]: g for g in r["spec"]["groups"]}
for rule in groups["e2e.alerts"]["rules"]:
    expr = rule["expr"]
    assert "max by (tier, exported_service, project, runner)" in expr, (rule["alert"], expr)
    for field in ("summary", "description"):
        text = rule["annotations"][field]
        assert "$labels.service " not in text and "$labels.service}" not in text, (rule["alert"], field)
        assert "$labels.exported_service" in text, (rule["alert"], field)
print("ok")
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ok"* ]]
}
```

### File 3 — docs

- `CHANGELOG.md` `[Unreleased]` → `### Fixed`: a prose entry. Explain that alert identity
  included the exporter pod, so a rollout re-paged an unchanged red run, and that the `service`
  collision made the subject name the exporter.
- This file: flip **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: the new test is RED at `HEAD` (paste output).
- [ ] Mutation: revert only the `E2EVerificationStale` expr to its old form; the new test goes
      red. Restore from a `$TMPDIR` snapshot and prove it with `cmp`.
- [ ] `bats scripts/tests/plugins/e2e_observability.bats` is green; paste the counts.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT change the exporter, its ServiceMonitor or `honorLabels`; that would re-key every
  exporter series.
- Do NOT change the `for:` durations, thresholds, labels or the dashboard.
- Do NOT apply anything to a cluster.
- Do NOT touch files outside those listed. No commit, push, PR or `--no-verify`.
