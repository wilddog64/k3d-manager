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

## Resolution

The exporter payload-normalization fix was committed as `8c80aeb9`, deployed,
and the live exporter restarted. A durable backfill event was published for the
latest retained run. The exporter now emits five group series:

```text
e2e_failure_group_info{kind="contract-drift",target="api/cart.spec.ts"} 11
e2e_failure_group_info{kind="contract-drift",target="api/cross-service.spec.ts"} 10
e2e_failure_group_info{kind="assertion",target="api/payments.spec.ts"} 9
e2e_failure_group_info{kind="assertion",target="api/orders.spec.ts"} 2
e2e_failure_group_info{kind="assertion",target="api/products.spec.ts"} 1
```

Refresh Grafana after its normal one-minute refresh interval. Future E2E
publications will carry groups directly; the backfill is only for this retained
run.

## Follow-up

Keep the focused exporter test and verify the next scheduled E2E publication
without a manual backfill.
