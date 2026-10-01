# Bug: Hermes dashboard findings have no drill-down evidence

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30
**Status:** FIXED (pending final commit SHA)
**Severity:** medium — the dashboard reports degraded sensors but does not expose the hostname,
CI run, or actionable evidence needed to diagnose them.

## Evidence

The **Current Hermes findings** table shows entries such as:

```text
reachability  single-service 1/7 hosts failing  degraded
ci            wilddog64/k3d-manager deploy failure degraded
```

The table has no link, row action, or expanded detail view. The `reachability` record actually
contains `data.failed_hosts`, and the `ci` record can contain repository/run data, but the Grafana
table transformation only displays `sensor`, `evidence`, `status`, and `target_namespace`.

## Root cause

The Hermes dashboard renders the summarized `hermes_sensor_status` metric but does not preserve or
link the structured diagnostic fields. Operators must leave Grafana and independently reconstruct
the failing endpoint or GitHub Actions run.

## Proposed fix

Add actionable evidence to the findings table without changing sensor semantics:

- show failed hostnames for reachability;
- show a clickable GitHub Actions run URL or run ID for CI findings;
- retain the existing evidence text and target namespace;
- keep the panel safe when structured data is absent.

## Acceptance

From the dashboard alone, an operator can identify the failing public hostname and open the failed
CI run. A missing optional field must not make the panel disappear or turn a healthy sensor into an
unknown one.
