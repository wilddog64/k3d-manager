# Bug: the hub recovery node map is hard-coded, and no longer matches the hub after the 2026-10-03 rebuild

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** DEFERRED (2026-10-10, Claude): not worth fixing in place. The only path that reads this map's node column, `hub_recovery_restore`, cannot read today's `make snapshot` archives anyway (`docs/howto/hub-snapshots.md`). The supported restore is v1.43.1 `hub_data_recover`, which pre-binds each claim to its recorded node. This doc is now an input to a future snapshot-restore design, not a v1.43.2 fix. Found during the DR drill live checks (`docs/plans/v1.43.0-hub-dr-drill.md` §7 L2).
**Priority:** P2 — the legacy snapshot restore refuses on today's hub; the workaround is a hand edit of the map
**Severity:** medium

## Symptom

```
$ ./scripts/k3d-manager hub_recovery_targets k3d-k3d-cluster
PV target node mismatch for secrets/data-vault-0.
rc=1
```

`_hub_recovery_records` (`scripts/plugins/hub_recovery.sh`) gives each claim a fixed logical node.
The live hub on 2026-10-09 has every listed claim on a different node:

| Claim | Map says | Live (`selected-node`) |
|---|---|---|
| `secrets/data-vault-0` | server-0 | agent-1 |
| `identity/postgres-keycloak-pvc` | agent-1 | agent-0 |
| `identity/data-openldap-0` | agent-0 | server-0 |
| `monitoring/prometheus-…-prometheus-0` | agent-0 | agent-2 |
| `monitoring/storage-loki-0` | agent-1 | server-0 |

## Cause

`local-path` uses `WaitForFirstConsumer`. Each claim is provisioned on whichever node the scheduler
picks for the first consumer, so placement changes with every rebuild. The map matched the hub
only while the hub was restored from its own `state.db` (2026-09-11), which brought the PV objects
back with their old `nodeAffinity`.

`hub_recovery_targets` refuses any claim whose node differs from the map. `hub_recovery_restore`
needs those targets, so a restore of an M2 snapshot into a rebuilt hub refuses unless the scheduler
happens to reproduce the old placement.

`hub_snapshot_capture` is not affected for correctness. It reads the live node for each claim and
records it in `MANIFEST.tsv`, but it names the storage directory from the map's column, so the
directory names in a snapshot do not describe where the data lived.

## Fix direction (to be specified)

- The expected node comes from the snapshot, never from a constant: the restore compares against
  the node recorded in `MANIFEST.tsv` (or, for the DR drill, `pv-pvc.yaml`).
- Before the consumer starts, the restore pre-binds each new claim to its recorded node with
  `volume.kubernetes.io/selected-node`, as the DR drill's D3 does. Then the placement matches by
  construction instead of by luck.
- `_hub_recovery_records` keeps only the claim list. Its node and storage columns go, or become
  informational.
- A regression test: a targets fixture with a placement different from the old map, but matching
  the manifest, passes.

The DR drill does not depend on this fix. Its node gate reads `pv-pvc.yaml` (plan D3 step 3).
