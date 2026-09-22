# Hub snapshots

Use `make snapshot` before a planned hub rebuild to copy the cold hub state to
the M2 store. The capture includes k3s server state, PV/PVC metadata, Vault's
file-backed data, Prometheus, Loki, Keycloak Postgres, OpenLDAP, and Trivy
local-path trees. It uses the existing `E2E_M2_SSH_HOST` alias; override it
with `K3DM_SNAPSHOT_HOST` or set `K3DM_SNAPSHOT_DIR` for another remote store.

`make snapshot-list` reports each timestamp, size, and verified/incomplete
state. `make snapshot-prune` deletes incomplete snapshots first and retains the
newest three verified snapshots by default. Change the ceiling with
`K3DM_SNAPSHOT_KEEP`; pruning refuses to remove the last verified snapshot.

Prometheus has a three-day retention ceiling (`--storage.tsdb.retention.time=3d`).
An older snapshot contains blocks Prometheus immediately prunes on startup, so
this feature preserves history across a down/up cycle within three days rather
than providing long-term history. Long-term history needs higher Prometheus
retention or remote write.

After rebuilding the hub, generate the new target map and restore the captured
directory with:

```bash
./scripts/k3d-manager hub_recovery_restore <captured-directory> <targets.tsv> --confirm
```

Capture is intentionally not wired into `make down` or `make up`; run it
explicitly while the hub is available and before teardown.
