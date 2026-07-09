# Bugfix: Trivy findings need ownership classification and a fixed-state dashboard contract

## Problem

The Trivy sections on the hub Grafana dashboard already show security findings, but they still behave like a passive snapshot:

- they show high/critical counts
- they list rows for current findings
- they explain some rows

What they do not do yet is separate:

- findings we should fix now
- findings we should accept as baseline or vendor-managed
- findings that were fixed but should remain visible as resolved history

That makes the dashboard useful for inspection, but not yet useful for triage automation.

## What Needs To Be Fixed

### Fix now

These are findings owned by this repo or by platform manifests we control:

- app-owned RBAC objects in `cicd`
- app-owned RBAC objects in `secrets`
- generated `argocd-*` roles and bindings that come from our manifests
- other repo-owned Roles / ClusterRoles that we can safely change through GitOps

These findings should be treated as actionable.
If a safe manifest correction exists, the automation should open or apply the fix through GitOps.
If no safe correction exists, the item should still be routed as an actionable ticket.

### Less concern

These are findings we should keep visible, but not auto-fix:

- built-in Kubernetes roles such as `cluster-admin`, `view`, and `edit`
- vendor-managed or chart-managed roles such as `istiod` / `istio-reader-*`
- platform add-ons owned by upstream charts, such as `external-secrets-*`, `kube-prometheus-stack-*`, and `trivy-operator-*`
- ephemeral test scaffolding or validation-only resources when they are not part of the long-lived platform baseline

These findings should be marked as accepted baseline or review-only, not silently remediated.

### Review-only

Any High/Critical finding with unclear ownership should default to review-only until the owning manifest is identified.

## Root Cause

The current dashboard is driven by current Trivy report data and Prometheus summaries.
That is enough to answer "what is failing now", but not enough to answer:

- who owns this row
- whether it is safe to auto-remediate
- whether it was previously fixed
- whether the row should still be visible as a resolved issue

The dashboard needs a materialized finding state, not just the latest scan result.

## Proposal

Add a small Trivy finding classification layer and make the dashboard consume it.

1. Build a finding catalog keyed by the Trivy finding identity.
2. Classify each row as `fix_now`, `accepted_baseline`, or `review_only`.
3. Materialize the latest state for each finding as `open`, `fixed`, or `accepted`.
4. Keep resolved rows visible long enough to show closure instead of disappearing immediately.
5. Only auto-remediate rows in the `fix_now` class.

## Data Model

Use a stable row key that survives dashboard refreshes:

- report kind
- namespace
- object name
- resource kind
- severity
- Trivy title / check ID

Store the following derived fields for every row:

- `classification`
- `ownership`
- `reason`
- `resolution_state`
- `last_seen`
- `fixed_at`

## Automation Contract

### Auto-fix

For `fix_now` rows, the automation may:

- patch the owning manifest through GitOps
- open a targeted issue or PR when the fix is not safe to apply automatically

The automation must not patch vendor-managed objects directly.

### Accept

For `accepted_baseline` rows, the automation should:

- keep the row visible
- suppress auto-remediation
- record why the row is accepted

### Mark fixed

When a finding disappears from the latest Trivy report:

- keep the row in the materialized state store
- mark it `fixed`
- retain it in the dashboard for historical context

The dashboard should not lose the row just because the next scan is clean.

## Dashboard Contract

Update the Trivy tables so they can show:

- `classification`
- `ownership`
- `reason`
- `resolution_state`

The existing Trivy drilldown panels should remain the source of truth for the current scan result, but the row rendering must reflect the materialized state:

- open finding -> `open`
- accepted baseline -> `accepted`
- resolved finding -> `fixed`

The top-level compliance panel should continue showing current failures, while the drilldown tables show whether a row is actionable or already resolved.

## Non-Goals

- changing Trivy Operator itself
- auto-patching built-in Kubernetes roles
- auto-patching vendor-managed chart resources
- suppressing Trivy visibility
- using the dashboard as an ACG sandbox signal

## Acceptance Criteria

- Repo-owned RBAC rows are classified as `fix_now`.
- Built-in and vendor-managed rows are classified as `accepted_baseline` or `review_only`.
- The dashboard can show `fixed` rows after the latest report goes clean.
- The tables explain why a High/Critical row exists and whether it is actionable.
- Auto-remediation is limited to safe, owned targets.

