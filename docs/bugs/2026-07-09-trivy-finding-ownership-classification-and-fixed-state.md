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

These are findings owned by this repo or by platform manifests we control. Measured against
`k3d-k3d-cluster` on 2026-07-10, the **complete** list is three namespaced Roles, all High, no Criticals:

| Namespace | Role | Failing check |
|-----------|------|---------------|
| `identity` | `role-ldap-password-rotator` | HIGH `AVD-KSV-0053` Exec into Pods |
| `secrets` | `role-ldap-password-rotator-vault` | HIGH `AVD-KSV-0053` Exec into Pods |
| `vcluster-probetest` | `role-vc-probetest` | HIGH `AVD-KSV-0053` Exec into Pods, HIGH `AVD-KSV-0056` Manage Kubernetes networking |

Both rotator Roles hold `pods/exec` because the rotator execs into the OpenLDAP pod to run
`ldappasswd`. The finding is legitimate and the fix is a design change, not an RBAC narrowing:
if the rotator binds over LDAPS instead of exec'ing, `AVD-KSV-0053` clears for the right reason.
That work is tracked with the existing "ldap rotator stdin fix" backlog item.
`role-vc-probetest` is test scaffolding and should be scoped down or torn down after the probe.

These findings should be treated as actionable.
If a safe manifest correction exists, the automation should open or apply the fix through GitOps.
If no safe correction exists, the item should still be routed as an actionable ticket.

> **Correction (2026-07-10).** Two earlier claims in this section were wrong and are retracted:
>
> - *"app-owned RBAC objects in `cicd`"* — the `cicd` namespace has eight `rbacassessmentreports`
>   (all `role-argocd-*`), but **none of them has a High or Critical count above zero**. There is
>   nothing to fix there.
> - *"generated `argocd-*` roles and bindings that come from our manifests"* — the ArgoCD
>   ClusterRoles are **chart-managed**, not ours:
>   `app.kubernetes.io/managed-by: Helm`, `helm.sh/chart: argo-cd-9.5.15`. Classifying them
>   `fix_now` would contradict this document's own rule that automation must not patch
>   vendor-managed objects. They belong in `accepted_baseline`.

### Less concern

These are findings we should keep visible, but not auto-fix. This is where **all 32** of the
cluster-scoped High/Critical findings land — every one is either Kubernetes itself or a third-party
chart, and none is authored by this repo:

- built-in Kubernetes roles such as `cluster-admin`, `admin`, and `edit`
- upstream `system:*` controller roles — `system:kube-controller-manager`, `system:node`,
  `system:controller:persistent-volume-binder`, `system:controller:namespace-controller`, and
  ~13 more. These ship with the distro and cannot be narrowed without breaking the cluster.
- k3s-specific built-ins such as `k3s-cloud-controller-manager` and `local-path-provisioner-role`
- vendor-managed or chart-managed roles such as `istiod` / `istio-reader-*`
- platform add-ons owned by upstream charts, such as `argocd-*`, `external-secrets-*`,
  `kube-prometheus-stack-*`, `loki`, and `trivy-operator-*`
- ephemeral test scaffolding or validation-only resources when they are not part of the long-lived platform baseline

These findings should be marked as accepted baseline or review-only, not silently remediated.

**Consequence for the dashboard.** The `Trivy Infra High/Critical Findings` stat currently sums
Roles and ClusterRoles together, so it reads as a large, alarming number that is ~91% upstream
Kubernetes RBAC we must not touch. Once classification exists, that stat should count `fix_now`
rows only, with the accepted baseline shown separately.

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

## Blocker: the classification cannot be built from Prometheus alone

This is load-bearing for the whole design and was not known when this doc was first written.

`trivy_clusterrole_clusterrbacassessments` exports the *report* name, not the object name. When
the real ClusterRole name is long or contains characters invalid in a resource name, trivy-operator
names the report `clusterrole-<hash>` and the metric inherits that. So the dashboard shows
`clusterrole-7c4d8f665`, and there is no series label anywhere that says what it actually is.

The real name exists on the report — but only as an **annotation**, which is never scraped:

```
metadata.labels:
  trivy-operator.resource.kind: ClusterRole
  trivy-operator.resource.name-hash: 7c4d8f665     # <- hash only
metadata.annotations:
  trivy-operator.resource.name: system:controller:persistent-volume-binder   # <- the real name
```

Neither the Trivy check ID (`AVD-KSV-0041`) nor the check title (`Manage secrets`) reaches
Prometheus either — both live in `.report.checks[]` on the CR. The metric value is a *count of
failing checks at a severity*, so a report failing two Critical checks emits a single series with
value `2` and no way to say which two.

**Therefore:** the classification layer must read the `*rbacassessmentreports` CRs via the
Kubernetes API, not scrape Prometheus. `scripts/etc/argocd/platform-ops/cve-scan.sh` is the
existing precedent for this shape — a scheduled job that reads cluster state, diffs it against a
checked-in expectation, and emits a single actionable signal. Model the classifier on it.

A Prometheus-only implementation of this document is not possible.

## Data Model

Use a stable row key that survives dashboard refreshes. Note that the first four fields are only
available from the CR, not from the metric — see the blocker above:

- report kind
- namespace
- object name — from the `trivy-operator.resource.name` **annotation**, not the metric's `name` label
- resource kind
- severity
- Trivy title / check ID — from `.report.checks[]`, not available in Prometheus

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

