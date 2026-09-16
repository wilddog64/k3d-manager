# Live E2E failure-groups table remains empty

## What was checked

Applied the updated platform-ops manifests with `make platform-ops` and
restarted `vulnerability-inventory-exporter`. The live exporter ConfigMap now
contains the `e2e_failure_group_info` implementation.

The three retained result ConfigMaps originally contained only aggregate data:

```text
run 1787838531-2562: failed=31 total=102
run 1789481773-13798: failed=45 total=102
run 1789549631-2079: failed=33 total=102
```

The newest event was backfilled with groups, but the live exporter still
emitted no `e2e_failure_group_info` series and represented that item as
`run_id="e2e-result-m2-d40431a29478"` with empty dimensions. This means the
exporter refresh path is falling back to the ConfigMap metadata instead of
parsing that event payload. The Grafana table therefore remains empty.

## Latest known failure groups

The redacted sidecar for run `1789549631-2079` contains 33 failures:

| Group | Count |
| --- | ---: |
| contract drift — `api/cart.spec.ts` | 11 |
| contract drift — `api/cross-service.spec.ts` | 10 |
| assertion — `api/payments.spec.ts` | 9 |
| assertion — `api/orders.spec.ts` | 2 |
| assertion — `api/products.spec.ts` | 1 |

## Follow-up

Make the exporter refresh path preserve and expose valid `event.json` payloads
with `failure_groups`, add a focused live-shaped exporter test, then rerun the
E2E publisher. Do not treat the dashboard as green until the group series and
the full-run result are both visible.
