# Hub snapshots

Use `make snapshot` before a planned hub rebuild to copy the cold hub state to
the M2 store. The capture includes k3s server state, PV/PVC metadata, Vault's
file-backed data, Prometheus, Loki, Keycloak Postgres, and OpenLDAP local-path
trees. It uses the existing `E2E_M2_SSH_HOST` alias; override it
with `K3DM_SNAPSHOT_HOST` or set `K3DM_SNAPSHOT_DIR` for another remote store.

`make snapshot-list` reports each timestamp, size, and verified/incomplete
state. After a successful capture, `make snapshot` automatically prunes to the
newest `K3DM_SNAPSHOT_KEEP` (default 3) verified snapshots. Set
`K3DM_SNAPSHOT_AUTO_PRUNE=0` to disable that automatic step. Auto-prune leaves
incomplete uploads alone; `make snapshot-prune` deletes incomplete snapshots
first and retains the newest verified snapshots. Change the ceiling with
`K3DM_SNAPSHOT_KEEP`; pruning refuses to remove the last verified snapshot.

Before upload, the capture checks that the M2 has enough free space for the
staging directory plus `K3DM_SNAPSHOT_MIN_FREE_GB` (default 20 GiB). A failed
preflight stops before rsync and leaves no incomplete directory. A snapshot is
roughly 3.3 GB today, so the default three-snapshot retention uses about 10 GB.

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

Each claim is stored as `<claim-dir>.tar`, captured by `tar` inside its node
container. The archive preserves owner, mode, and setgid bits; the host does
not apply those attributes. Restore extracts it inside the node with
`docker exec -i <node> tar -C <path> -xpf -`. Restore itself remains the
v1.43.0 DR drill's scope.

`hub_recovery_restore` and `hub_recovery_plan` still read the older directory
layout (`server-db/state.db` and `pvc-*` directories), not these `.tar` files.
Until the v1.43.0 DR drill teaches them the archive layout, the restore command
above does not accept a snapshot taken with `make snapshot`.

Deleting the local Hub is guarded by the newest verified M2 snapshot. The
snapshot must be no older than 24 hours; otherwise `--delete-hub` refuses
before any teardown starts. `make down DELETE_HUB=1` therefore requires a
fresh `make snapshot`. To explicitly accept permanent loss of the seven
mapped Hub claims, use `make down DELETE_HUB=1 DISCARD_HUB_DATA=1` (or
`--discard-hub-data` with `bin/cluster-down`).

Successful captures write a local timestamp stamp at
`~/.local/share/k3d-manager/hub-snapshot-last`. Text `make status` reports
its age without contacting the M2; JSON status is unchanged.

Run `make hub-retain-pvs` as an operator after the Hub is running and after
each rebuild. It patches the mapped claims' PVs to `Retain`, is idempotent,
and continues processing after a missing PVC. Retain protects data from PVC
deletion only. `k3d cluster delete` removes node containers and their
storage regardless, so the delete guard remains necessary. A rebuilt Hub
creates PVs with `Delete`, so rerun the target after rebuilding.

The seven captured claims are `data-vault-0`, `postgres-keycloak-pvc`,
`ldap-data-pvc`, `data-openldap-0`, `ldap-config-pvc`, the Prometheus data
claim, and `storage-loki-0`. The Trivy database is deliberately excluded
because it is a re-downloadable cache; vulnerability reports are already
preserved in `server-db.tar`.

Uploads first use `<timestamp>.INCOMPLETE/`. A snapshot is renamed to the bare
timestamp only after the remote `sha256sum -c SHA256SUMS` succeeds. Failed or
interrupted uploads therefore remain visibly incomplete and cannot satisfy the
verified-snapshot guard.
