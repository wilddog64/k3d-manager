# Host disk (`k3dm-host-disk`) — hub

[← Grafana dashboards index](../grafana-dashboards.md)

Hermes ticks every five minutes and runs `bin/k3dm-disk-metrics`, which probes the M4 locally,
the M2 over the existing SSH alias, and the Hostinger node (`/`) over SSH with the
`HOSTINGER_*` settings before pushing gauges to the hub Pushgateway. The
dashboard shows used percentage, free GiB, probe status, and Pushgateway age for each host.

80% used sends a warning email. 90% used or less than 20 GiB free sends a critical SMS; M2
alerts recommend `make snapshot-prune` / lowering `K3DM_SNAPSHOT_KEEP`, while Hostinger alerts
recommend pruning unused k3s images (`sudo k3s crictl rmi --prune`) and checking logs. M4 alerts
recommend `docker system df` and pruning images. A `No data` panel means Hermes is not running
or the Pushgateway port-forward is down.

The dashboard syncs from git through the `grafana-dashboards-hub` ApplicationSet. The alert rules
do not: apply them with `make prometheus-rules`, which applies only
`scripts/etc/prometheus/rules/*.yaml` to the hub, without the full `make observability` redeploy.

## OrbStack

The **OrbStack** stat shows the installed version and whether an update is available. The **OrbStack upgraded** annotation marks when a new version first appears, over the restart interval.
