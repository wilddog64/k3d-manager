# Bug: Firing Alerts by Category omits when alerts started firing and how long they have been active

**Filed:** 2026-10-21 (operator screenshot)
**Status:** OPEN — evidence from Grafana screenshot and dashboard source; implementation not started
**Priority:** P3 — observability usability; alert detection and delivery not shown to be broken
**Severity:** low
**Approval:** operator requested filing a P3 bug on 2026-10-21; no implementation authorization
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Branch:** `k3d-manager-v1.43.5`
**Found by:** operator, Grafana at approximately 13:40 PDT on 2026-10-21
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml`, `scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml`, `scripts/tests/plugins/grafana_dashboard_appsets.bats`, `docs/guides/grafana-dashboards.md`
**Related:** `docs/bugs/2026-10-02-grafana-overview-firing-alerts-and-request-rate-no-data.md`, `docs/bugs/2026-10-02-grafana-overview-readable-title-collides-with-stock-dashboard.md`

## Problem

The **Grafana Health & Firing Alerts** dashboard reports **41** firing Prometheus alerts, with its
**Firing Alerts by Category** table grouped into:

- `TrivyCriticalVulnerabilityDetected` — hub 25, ubuntu-hostinger 14 (image vulnerabilities)
- `HostDiskMetricsStale` — hub 1
- `TargetDown` — acg 1

The table currently exposes **Category, Alert, Severity, Cluster, Count** but not **Fired at**
or **Firing for**. An operator cannot distinguish longstanding upstream-image CVE alerts
from newly firing operational warnings or determine when a `TargetDown` instance started.
The headline count alone does not establish recency or duration.

## Source diagnosis / constraints

The dashboard's existing table aggregates `ALERTS{alertstate="firing"}` by
alert category/name/severity/cluster. Aggregation discards individual alert-instance
identity and timing; `ALERTS` itself is a state gauge, not a firing-start timestamp.

`ALERTS_FOR_STATE` can indicate when a rule entered its pending/active state, which
may precede its transition to *firing* when the rule defines `for:`. Therefore
`time() - ALERTS_FOR_STATE` must **not** be labeled as exact firing age.
Prometheus rule API `activeAt` likewise may denote active/pending entry.
Alertmanager alert `startsAt` and/or event-state data may be more appropriate,
subject to validating semantics on the deployed Prometheus/Alertmanager version.

This bug is about exposing reliable temporal context. It does not assert that
any alert rule, notification, or ingestion pathway is failing.

## Expected behavior

Keep the current aggregated category counts, but provide an accessible view of each
*firing alert instance* with:

- alert name, severity, cluster, and identifying labels or a link to its detail;
- **Fired at** timestamp and **Firing for** duration derived from a source whose
  semantics really represent firing (or clearly relabel an earlier `active/pending since`
  timestamp if precise firing time is unavailable);
- unambiguous timezone, timestamp provenance, and safe fallback when timing is unavailable.

Optionally add a last-24-hour state/timeline view for alert transitions, if event history
is available and retention/cardinality are suitable. Do not invent a resolved timestamp
for a presently firing alert.

## Proposed fix scope

1. Determine the source and exact semantics of timestamps for the deployed
   Prometheus + Alertmanager stack. Verify whether Alertmanager `startsAt`,
   Prometheus rule state, or another existing metric/API supplies the required timing.
2. Preserve the aggregate **Firing Alerts by Category** panel. Add a bounded
   per-instance detail table or drilldown that separates individual instances
   (especially the 39 Trivy CVE findings) rather than pretending one grouped row
   has one shared firing start.
3. Use correctly labeled **Fired at** and **Firing for**, or disclose a fallback
   such as **Active since (includes pending)**. Avoid misleading exactness.
4. Design safe access to the data; never embed bearer tokens in dashboard JSON,
   widen external access, or expose sensitive alert labels unnecessarily.
5. Add offline source/query/shape tests and document where to inspect alert history.

## Acceptance

```yaml
must:
  - id: M1
    text: The existing aggregated Firing Alerts by Category counts remain available and correct.
  - id: M2
    text: Operators can inspect each currently firing alert instance's grounded start-time context and elapsed duration, with an explicit timezone.
  - id: M3
    text: Any timestamp labeled Fired at reflects a verified firing transition; a pending/active timestamp is labeled differently.
  - id: M4
    text: Missing timestamps, no firing alerts, and multiple instances of one alert are handled without fabricated values.
  - id: M5
    text: Source access, alert labels and panel/cardinality limits remain safe, and the dashboard guide documents semantics.
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
    proves: [M1, M2, M3, M4, M5, N1, N2, N3]
    text: Fixtures cover distinct alerts, distinct instances of one rule, a rule with a pending for interval, missing timestamp, and zero alerts; dashboard tests pass and show red on pre-fix representation.
  - id: E2
    kind: live
    proves: [M1, M2, M3, M4]
    text: After separately approved rollout, compare at least one Trivy instance and one operational warning against authoritative API timestamps while the current aggregate totals remain correct.
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml
  - scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml
  - scripts/tests/plugins/grafana_dashboard_appsets.bats
  - docs/guides/grafana-dashboards.md
```

## Definition of Done

- [ ] Timestamp provenance and pending-versus-firing semantics documented.
- [ ] Firing alert details expose correct per-instance time/age and retain summary counts.
- [ ] Targeted dashboard/query tests and pre-fix regression demonstration attached.
- [ ] Operator separately approves implementation and live verification E2.
- [ ] Record fix SHA, verification evidence and status transition in this bug.

## What NOT to Do

- Do NOT create a PR, merge, or commit to `main`.
- Do NOT deploy anything or modify implementation code as part of filing.
- Do NOT infer firing timestamps from the screenshot's 41-alert count.
- Do NOT add unbounded per-alert Prometheus labels or expose credentials in Grafana.
