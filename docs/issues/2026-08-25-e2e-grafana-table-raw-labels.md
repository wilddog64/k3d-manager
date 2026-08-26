# E2E Grafana table shows raw and duplicate labels

## Finding

The `Recent runs` panel in `scripts/etc/argocd/platform-ops/grafana-dashboard-e2e.yaml`
queries the instant vector directly:

```text
e2e_run_info{service=~"$service",tier=~"$tier",runner=~"$runner"}
```

Its organize transformation excludes infrastructure labels (`job`, `instance`,
`container`, `endpoint`, `namespace`, `pod`) but does not exclude or rename the
two service dimensions. The result therefore displays both `service` (the
exporter service) and `exported_service` (the application), which appears as a
duplicate service column. Older result ConfigMaps also have empty `failed`,
`total`, and duration values, so those columns are blank for historical rows.

## Evidence

The M2 result record is present in the hub:

```text
{"run_id": "1787708603-5833", "tier": "vcluster", "runner": "m2", "service": "product-catalog", "project": "api+flows", "candidate_digest": "", "passed": "false", "total": "102", "failed": "45", "duration_seconds": "67.869", "timestamp": "2026-08-26T01:52:03.423304+00:00", "commit": "f5a40988d11f00e579d5bad521b13aa8d189ce40"}
```

The panel's current query and transformation are:

```text
expr: e2e_run_info{service=~"$service",tier=~"$tier",runner=~"$runner"}
exclude: Time, Value, __name__, job, instance, container, endpoint, namespace, pod, service_label
```

## Impact

The table is technically populated, but it is difficult to read and older
records look incomplete. The dashboard does not present a concise application
service column or distinguish unavailable legacy fields from a zero value.

## Recommended fix

Use an exporter/dashboard contract that emits a single canonical application
service label, preserves numeric totals for new runs, and provides an explicit
unknown marker for legacy records. Update the panel transformation to hide
`service` (exporter identity), rename `exported_service` to `Service`, and keep
`run_id`, `runner`, `project`, `passed`, `total`, `failed`, `duration_seconds`,
`timestamp`, and `commit`. Add a focused dashboard fixture test that rejects
duplicate service columns and verifies legacy rows render safely.

This is separate from the M2 API-contract blocker recorded in
`docs/issues/2026-08-25-m2-e2e-acceptance-contract-mismatch.md`.
