# Bugfix: Trivy High/Critical findings should trigger actionable alerts, not just passive Grafana panels

## Problem

The hub Grafana dashboard already exposes Trivy security data:

- `Trivy Infra High/Critical Findings`
- `Trivy Cluster Compliance`
- `Trivy Infra RBAC Findings`
- `Trivy ClusterRole Findings`

Those panels are useful for inspection, but they are still passive. An operator has to notice the counts or tables manually. That means a newly introduced `High` or `Critical` security issue can sit on the dashboard without any alert, ticket, or explicit triage step.

## Root Cause

The current observability stack has alerting for Trivy Operator scan job failures, but not for the security findings that the dashboard already summarizes.

In practice:

- the dashboard queries `trivy_role_rbacassessments`
- the dashboard queries `trivy_clusterrole_clusterrbacassments`
- the dashboard queries `trivy_cluster_compliance`

but there is no alert rule that turns those findings into operator action.

## Proposal

Add an automated finding-to-action path for Trivy security results:

1. Alert when infra `High`/`Critical` findings are present.
2. Alert when cluster compliance reports any failing checks.
3. Route those alerts through the existing analyzer webhook path so they become visible immediately.
4. Document the triage contract so the findings are treated as real work, not dashboard noise.

This is detection and triage automation, not auto-remediation. RBAC and compliance issues should still require human review before any manifest changes.

## Required Fix

- Add Prometheus alert rules for the Trivy finding queries already used by the dashboard.
- Route the new alerts through the same alerting path used by the existing ArgoCD / Trivy operator alerts.
- Add regression coverage so the alert queries, routes, and dashboard contracts stay aligned.
- Record the operator workflow in docs so `High`/`Critical` findings are handled consistently.

## Recommended Alert Shape

Use the same severity split the dashboard already shows:

- `High` findings are actionable and should page/notify.
- `Critical` findings are urgent and should page/notify immediately.

The alert should fire on the presence of non-zero findings, not on dashboard visibility.

## Out of Scope

- automatic RBAC widening or narrowing
- automatic manifest edits
- suppressing the dashboard panels
- treating the Trivy output as an ACG sandbox signal

## Expected Outcome

- Grafana remains the visual summary.
- Alerts provide the automation.
- Operators no longer have to notice new `High` / `Critical` Trivy findings by hand.
- Known security regressions become visible through the same workflow as other cluster health regressions.
