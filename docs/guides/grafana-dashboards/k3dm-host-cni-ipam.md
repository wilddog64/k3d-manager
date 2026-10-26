# k3dm Host Pod IP Pool (`k3dm-host-cni-ipam`)

[← Grafana dashboards index](../grafana-dashboards.md)

The hub dashboard tracks pod IP allocation on the Hostinger node. Hermes publishes these
metrics to the hub Pushgateway after collecting the host's CNI IPAM state.

| Panel | Metric or query | Meaning |
|---|---|---|
| Pool used % | `100 * k3dm_cni_ipam_reservations / k3dm_cni_ipam_range_size` | Current allocation percentage; warning at 80%, critical at 90%. |
| Reservations | `k3dm_cni_ipam_reservations`, `k3dm_cni_ipam_range_size` | Used and total addresses. |
| Allocation errors (1h) | `k3dm_cni_ipam_alloc_errors_1h` | Allocation errors during the last hour. |
| Probe status | `k3dm_cni_ipam_probe_success` | Whether the collector read the host state. |
| Pool used % over time | reservation count / range size | Allocation history. |
| Stale reservations removed per sweep | `k3dm_cni_ipam_stale_last_run` | Reservations cleaned in the latest sweep. Zero is normal unless utilization is unexpectedly high. |
| Since last sweep | `time() - k3dm_cni_ipam_sweep_last_run_timestamp_seconds` | Age of the last cleanup. |
| Last push age | `time() - max(push_time_seconds{job="k3dm-cni-ipam"})` | Age of the Pushgateway publication. |
| In use | `k3dm_cni_ipam_kept - k3dm_cni_ipam_skipped` (falls back to `kept`) | Reservations backed by a running pod sandbox. |
| Starting (grace period) | `k3dm_cni_ipam_young` | Reservations younger than the grace period, left alone while the pod starts. |
| Held without a sandbox | `k3dm_cni_ipam_skipped` | Reservations with no sandbox that the sweep keeps because a pod still reports the IP. This is the cleanup health signal; zero is normal. |
| Oldest held without a sandbox | `k3dm_cni_ipam_skipped_oldest_age_seconds` | Age of the oldest such reservation; orange at 30 min, red at 1 h. |
| Reservations by outcome | the four series above | History of the third row. |

`No data` means Hermes or the hub Pushgateway port-forward is unavailable. A down probe means
the collector cannot read `/var/lib/k3dm/cni-ipam-sweep.state` over SSH. High pool usage with
zero stale reservations removed indicates real pod load rather than a reservation leak. Check
`systemctl list-timers k3dm-cni-ipam-sweep.timer`, inspect the state file on the host, and run
`bin/k3dm-cni-ipam-metrics --dry-run` on the hub. See [shared triage](shared-operations.md#triage-no-data-by-cause).

The third row splits kept reservations by outcome. `needs host refresh` in the two *held without a
sandbox* panels means the host still runs a sweep from before v1.43.9, which does not write the
`skipped` keys; run `make refresh CLUSTER_PROVIDER=k3s-hostinger`. `HostCniIpamOrphanNotReclaimed`
fires when a reservation has been held without a sandbox for over an hour; see
[alerting triage](../alerting.md).
