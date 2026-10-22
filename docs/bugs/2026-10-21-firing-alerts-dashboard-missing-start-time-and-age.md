# Bug: Firing Alerts by Category omits when alerts started firing and how long they have been active

**Filed:** 2026-10-21 (operator screenshot)
**Status:** VERIFIED (offline) — identity/browser-local-time follow-up landed as `28e74901`; live verification found Argo CD still serving the prior revision; Category/identity column follow-up dispatched
**Priority:** P3 — observability usability; alert detection and delivery not shown to be broken
**Severity:** low
**Approval:** operator approved follow-up investigation, bug update, and fix dispatch on 2026-10-22
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Branch:** `k3d-manager-v1.43.5`
**Found by:** operator, Grafana at approximately 13:40 PDT on 2026-10-21
**Component:** Grafana alert and Trivy vulnerability panels; vulnerability inventory exporter
**Related:** `docs/bugs/2026-10-02-grafana-overview-firing-alerts-and-request-rate-no-data.md`, `docs/bugs/2026-10-02-grafana-overview-readable-title-collides-with-stock-dashboard.md`

## Initial finding and live follow-up

The **Grafana Health & Firing Alerts** dashboard reports **41** firing Prometheus alerts, with its
**Firing Alerts by Category** table grouped into:

- `TrivyCriticalVulnerabilityDetected` — hub 25, ubuntu-hostinger 14 (image vulnerabilities)
- `HostDiskMetricsStale` — hub 1
- `TargetDown` — acg 1

The original aggregate table exposed **Category, Alert, Severity, Cluster, Count** but not
time or duration. Offline follow-up `63d53576` added a per-alert table. The operator's live
Grafana screenshot on 2026-10-22 verified the panel is present, but found that it is too wide
and exposes raw labels with unclear meaning: `__name__` repeats `ALERTS_FOR_STATE`, while
`group` and `tier` are not useful operator-facing fields. The displayed time is epoch-like,
and the panel title does not answer when a CVE was detected. This is a presentation and
timestamp-provenance defect, not evidence that alerts or CVE detection are failing.

The user accepted a two-view design: retain a compact general alert-instance view, and add a
separate CVE-focused view with a clearly labeled VulnerabilityReport report-created time.
That report timestamp must not be presented as the first time the vulnerability was detected.
True first-seen time would require persisted historical state and is explicitly outside this
dispatch.

After a Grafana browser refresh, the operator confirmed the new readable time and compact
columns appeared. The follow-up screenshot showed repeated Trivy rows with only alert name,
cluster, namespace, severity, active-since, and duration; it still did not identify which app,
pod, or workload the row concerns. The allowlist hid too much context, so this issue is reopened.

## Source diagnosis / constraints

The dashboard's existing table aggregates `ALERTS{alertstate="firing"}` by
alert category/name/severity/cluster. Aggregation discards individual alert-instance
identity and timing; `ALERTS` itself is a state gauge, not a firing-start timestamp.

`ALERTS_FOR_STATE` stores the rule's active timestamp as a Unix epoch. It can precede
the firing transition when the rule defines `for:`. Therefore this value and its duration
must be clearly labeled **Active since (UTC; pending included)** and **Active for**; neither
is an exact firing start or CVE detection time. The Trivy alert rule has a `for: 15m`.
The current inventory exporter reads VulnerabilityReport objects and finding details, but
does not expose the report's `metadata.creationTimestamp`.

This bug is about exposing reliable temporal context. It does not assert that
any alert rule, notification, or ingestion pathway is failing.

## Expected behavior

Keep the current aggregated category counts and deliver two focused detail views:

- The general alert-instance table uses this exact operator-facing order: **Namespace →
  Cluster → Alert → App/pod identity → Active since → Active for**. The App/pod identity
  slot shows available `app` and `pod`/`instance` values (adjacent within that slot if both
  are present); do not fabricate missing identity. Hide `__name__`, `group`, `tier`, and
  other irrelevant/raw labels; retain an explicit pending-included caveat. Set the dashboard
  timezone to browser-local so timestamps follow the viewer's laptop/browser timezone.
- A separate bounded CVE finding table with CVE ID, severity, cluster, namespace, image,
  workload/report owner, package, installed/fixed version, and **Report created at (local)**
  sourced from the VulnerabilityReport `metadata.creationTimestamp`. Do not call this field
  “Detected at,” “First seen,” or imply it is the vulnerability's initial detection time.

The Prometheus samples remain Unix timestamps; Grafana performs timezone display conversion.
Do not change stored timestamps or elapsed-duration calculations for local display.

The Trivy alert rule groups by cluster, namespace, and image repository, and sets `app` from
the image repository; it does not preserve a pod label. Do not change this alert aggregation
or fabricate a pod identity. The CVE report's `resource_name` provides workload/report-owner
context in the separate finding view.

True first-detected time needs retained historical state and is out of scope. Do not add a
timeline or invent a resolved/first-seen timestamp.

## Proposed fix scope

1. Preserve aggregate category counts and make the general alert-instance view compact,
   human-readable, and explicitly active-since (not fired-at).
2. Export report creation time as a numeric timestamp metric/value from the existing
   VulnerabilityReport metadata path; do not encode timestamps as Prometheus labels.
3. Add the dedicated CVE finding view, with bounded rows/columns and truthful report-time
   semantics. Do not add first-detected history in this work.
4. Keep the two embedded dashboard definitions synchronized; update exporter/dashboard
   regression tests and the Trivy/shared-operations guidance.
5. Preserve credential secrecy, avoid unnecessary sensitive labels/cardinality, and do not
   change alert rules, routing, receivers, or production resources.

## Acceptance

```yaml
must:
  - id: M1
    text: The existing aggregated Firing Alerts by Category counts remain available and correct.
  - id: M2
    text: The general alert table columns are ordered Namespace, Cluster, Alert, Category, App/pod/instance identity, Severity, Active since (local; pending included), Active for; Category classification matches the aggregate panel, Severity is adjacent to identity, available target identifiers remain visible, and Grafana uses browser-local timezone.
  - id: M3
    text: No active-state timestamp is labeled as firing time or CVE detection time; the caveat is visible.
  - id: M4
    text: Missing timestamps, no firing alerts, and multiple instances of one alert are handled without fabricated values.
  - id: M5
    text: A separate CVE detail view exposes VulnerabilityReport creation time labeled Report created at (local), plus image and workload/report-owner context.
  - id: M6
    text: Source access, labels, cardinality, row limits, and dashboard definitions remain safe and synchronized; guides document semantics.
must_not:
  - id: N1
    text: Aggregated Trivy findings are assigned one invented common start time.
  - id: N2
    text: ALERTS_FOR_STATE or Prometheus activeAt is labeled as firing time without handling the rule's for interval.
  - id: N3
    text: No alert rules, routing, notification receivers, or production resources are changed merely to expose timestamps.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M5, M6, N1, N2, N3]
    text: Exporter and dashboard fixtures cover report timestamp/absence, distinct alerts and instances, pending interval, zero findings/alerts, exact alert-column order and available app/pod/instance identity, CVE report owner, browser-local timezone and timestamp units, limits, and synchronized dashboard definitions.
  - id: E2
    kind: live
    proves: [M1, M2, M3, M4]
    text: After separately approved rollout, confirm the general alert view identifies app and available pod/instance, the CVE view identifies image and report owner, both timestamps render in the viewer's browser-local timezone, and Report created at matches VulnerabilityReport metadata.creationTimestamp after timezone conversion; verify aggregate counts. This does not verify first-detected time.
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml
  - scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml
  - scripts/tests/plugins/grafana_dashboard_appsets.bats
  - scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml
  - scripts/tests/plugins/e2e_observability.bats
  - docs/guides/grafana-dashboards/shared-operations.md
  - docs/guides/grafana-dashboards/trivy-security.md

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml`
- `scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml`
- `scripts/tests/plugins/grafana_dashboard_appsets.bats`
- `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`
- `scripts/tests/plugins/e2e_observability.bats`
- `docs/guides/grafana-dashboards/shared-operations.md`
- `docs/guides/grafana-dashboards/trivy-security.md`

## Previous verification (2026-10-22)

Landed as `63d53576`. `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` passed 44/44; `shellcheck -x scripts/tests/plugins/grafana_dashboard_appsets.bats`, `_agent_lint`, `_agent_audit`, and `git diff --check` passed. The live screenshot subsequently showed the implementation did not meet usability/provenance expectations, so this result is historical offline evidence only; do not treat the issue as resolved or LIVE-VERIFIED.

## Follow-up verification (2026-10-22)

The scoped fix landed and was pushed to `k3d-manager-v1.43.5` as `309d77bf`.
Independent offline verification:

- `bats scripts/tests/plugins/grafana_dashboard_appsets.bats`: 45/45 passed.
- `bats scripts/tests/plugins/e2e_observability.bats`: 25 passed, 2 expected skips (`promtool` unavailable).
- `shellcheck -x scripts/tests/plugins/grafana_dashboard_appsets.bats scripts/tests/plugins/e2e_observability.bats`: passed, no diagnostics.
- `_agent_audit` and `_agent_lint`: passed (AI lint is disabled in this environment).
- `git diff --cached --check`: passed.
- `make check-doc-links`: `check-doc-links: 2311 file(s) OK`.
- Dispatcher landing gate reran both BATS suites, ShellCheck, and doc links after rebase; passed.

Offline verification covers the compact active-alert table, preserved category counts, bounded CVE table, synchronized dashboard panels, and report timestamp provenance/absence. This is **not LIVE-VERIFIED**. Operator should inspect the deployed Grafana dashboard after rollout and compare one displayed **Report created at (UTC)** value against that finding's VulnerabilityReport `metadata.creationTimestamp`; confirm active-since is readable UTC, raw labels are hidden, and category counts remain. First-detected time is not represented.

## Follow-up dispatch approval (2026-10-22)

- Live finding: generic table is too wide; `__name__` repeats the metric name; `group`/`tier` are unclear/noisy; displayed timestamp is epoch-like; no CVE report/detection time is shown.
- Approved disposition: compact generic active-alert context plus a separate CVE-focused finding table with VulnerabilityReport creation timestamp, explicitly not first-detected time.
- Dispatch scope is the `interface` list and `Files` below. Tests must cover timestamp provenance, absent timestamps, field selection/units, limits, and synchronized dashboard payloads. No deployment/live mutation is authorized by this dispatch.

## Actionable target identity follow-up (2026-10-22)

- Live result: timestamp formatting and label reduction are now visible, but repeated Trivy rows do not identify the affected app or target. The app/pod/workload context was over-pruned.
- Source finding: Trivy alert labels include `app` mapped from `image_repository`, but the rule aggregates by image and has no pod label. The CVE exporter already has `resource_name`, but the CVE table omits it.
- Approved change: add available `app`, `pod`/`instance` identifiers to the general table and `resource_name` as workload/report-owner context in the CVE table. Keep tables focused; do not expose noisy metric labels or alter alert grouping to invent pod-level identity.
- Operator specified the exact general-table order: **Namespace → Cluster → Alert → App/pod identity → Active since → Active for**. Do not add Severity to this table; severity and full finding context remain in the separate CVE view.
- Operator requested both timestamps use the viewer's laptop/browser-local timezone rather than forced UTC. Set the dashboard JSON `timezone` to `browser`; keep the underlying Unix timestamps and elapsed duration semantics unchanged.
- Redispatch only within the existing `Files` list. No rollout/live mutation is authorized.
- Live Grafana follow-up: operator screenshot still shows the previous Alert, Cluster, Namespace, Severity, Active-since (UTC) layout. Read-only Kubernetes inspection confirmed Argo CD `hub-grafana-dashboards` reports `Synced`/`Healthy` at revision `3b70efd16869a89fca3965eb8bcebf6fe9ae9d80`; the ConfigMap still has `timezone: utc` and the old panel fields. The landed browser-local-time fix is `28e74901`, so this screenshot does not exercise that fix. Operator clarified Severity must remain adjacent to App/Pod identity; requested order is Namespace, Cluster, Alert, identity, Severity, Active since, Active for. Dispatch this column-placement follow-up; do not force Argo refresh/sync without approval.
- Operator further clarified the exact active-alert column order: **Namespace → Cluster → Alert → Category → App/Pod identity → Severity → Active since → Active for**. Add Category classification to the per-instance rows using the same categories as the aggregate panel; do not remove Severity or alter alert grouping. The current worker must update dashboard definitions, regression assertions, and guidance within the existing file scope.

## Definition of Done

- [x] Active-since versus firing and report-created versus first-detected semantics are explicit.
- [ ] Generic table is compact/readable and orders Namespace, Cluster, Alert, Category, App/pod/instance identity, Severity, Active since, Active for; CVE detail includes report owner and report-created time while retaining aggregate counts.
- [x] Targeted exporter/dashboard tests cover timestamp provenance, missing values, target fields, bounds, and synchronized definitions.
- [ ] Operator separately approves live verification E2 after implementation is landed and deployed.
- [x] Record fix SHA, verification evidence and status transition in this bug.

## Identity and local-time follow-up verification (2026-10-22)

The follow-up landed and was pushed to `k3d-manager-v1.43.5` as `28e74901`.
Independent verification and dispatcher landing gates passed:

- `bats scripts/tests/plugins/grafana_dashboard_appsets.bats scripts/tests/plugins/e2e_observability.bats`: 70 passed, 2 expected skips because `promtool` is unavailable.
- `shellcheck -x scripts/tests/plugins/grafana_dashboard_appsets.bats scripts/tests/plugins/e2e_observability.bats`: clean.
- `_agent_audit`, `_agent_lint`, staged diff check, and `git diff --check`: passed.
- `make check-doc-links`: `check-doc-links: 2311 file(s) OK`.
- Dispatcher landing gate reran both BATS suites, ShellCheck, doc links, and diff check: passed.

The active-alert table orders Namespace, Cluster, Alert, available App/Pod/Instance identity,
Active since (local; pending included), and Active for. Dashboard timezone is `browser`; source
timestamps and elapsed-duration semantics are unchanged. The CVE finding table includes the
workload/report owner and labels VulnerabilityReport creation time as Report created at (local).
This is VERIFIED offline, not LIVE-VERIFIED. After deployment, operator should confirm the
column order and identity values, viewer-local timestamp rendering, report-owner context, and
category counts in Grafana. No deployment or live mutation was performed.

## What NOT to Do

- Do NOT create a PR, merge, or commit to `main`.
- Do NOT deploy anything or modify implementation code as part of filing.
- Do NOT infer firing timestamps from the screenshot's 41-alert count.
- Do NOT add unbounded per-alert Prometheus labels or expose credentials in Grafana.
- Do NOT claim VulnerabilityReport creation time is the CVE's first-detected time; historical first-seen tracking is out of scope.
