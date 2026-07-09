# Bugfix: Trivy infra security panels need object-level drilldown, not only aggregate counts

## Problem

The Trivy section on the hub dashboard is informative, but too broad when you
need to identify the actual culprit:

- `Trivy Infra High/Critical Findings` only shows the aggregate count
- `Trivy Cluster Compliance` mixes pass and fail rows together
- the RBAC and ClusterRole tables are specific, but they do not provide a
  combined top-level drilldown for the total finding count

That makes the dashboard good for “something is wrong” but weak for “what
exactly is wrong?”

## Root Cause

The current panels are built as status summaries:

- one stat over all high/critical RBAC and ClusterRole findings
- one compliance table over all statuses
- separate RBAC and ClusterRole tables for more detail

There is no combined drilldown view that shows the actual offending objects
behind the top-level count, and the compliance panel does not focus on the
failures.

## Fix

Add a drilldown-oriented Trivy view that:

1. keeps the aggregate count for a quick glance,
2. adds a combined finding table with exact object identity,
3. limits compliance visibility to failing checks,
4. adds a click-through link from the summary panels to the drilldown panel.

The drilldown should preserve the existing Trivy signal, but make the current
offenders obvious without manual cross-reading.

## Required Changes

`scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`

**OLD**
```promql
sum by (title,status) (trivy_cluster_compliance)
```

**NEW**
```promql
sort_desc(sum by (title,status) (trivy_cluster_compliance{status="Fail"}))
```

Add a new drilldown table panel that combines RBAC and ClusterRole findings
with a normalized `resource_name` column and a `source` label.

Also add a panel link on the summary panels so the operator can jump straight
to the combined drilldown view instead of reading the whole dashboard top to
bottom.

## Expected Outcome

- the dashboard still shows the total severity signal
- the drilldown table tells operators which object is responsible
- compliance noise is reduced to the failing rows only
- the Trivy section becomes useful for triage, not just status
