# Coordinated OrbStack upgrade

OrbStack updates stop the local Kubernetes hub. Use a planned window and run the coordinated command from this checkout:

```bash
DRY_RUN=1 make orbstack-upgrade
make orbstack-upgrade
```

The dry run performs read-only preflight checks and prints the recovery plan. A real run refuses unless an update is available, the hub is idle, the current context is `k3d-k3d-cluster`, the DR unseal copy is present, and the hub-data export timestamp is less than 24 hours old. Export freshness comes from `${K3DM_HUB_DATA_DIR:-$HOME/.k3dm/hub-data}/last-success`, which contains a UTC stamp such as `20261026T093000Z`.

The command requires a TTY and a typed `yes` before calling `orbctl update`. The default Pushgateway base is `http://localhost:19094`; set `K3DM_ORBSTACK_PUSHGATEWAY_URL` to use another endpoint. Recovery wait defaults are 300 seconds for the Vault watchdog interval, 10 seconds between readiness probes, and 900 seconds for the readiness timeout. Tests or controlled rehearsals can shorten them with `ORBSTACK_UPGRADE_WATCHDOG_WAIT`, `ORBSTACK_UPGRADE_POLL_INTERVAL`, and `ORBSTACK_UPGRADE_READY_TIMEOUT`.

After OrbStack restarts, the command waits for Docker, the hub API and Ready nodes. It allows the Vault watchdog to unseal Vault before using `hub_data_unseal_dr`, repairs Vault Kubernetes auth only when vault-0 was recreated and a SecretStore is invalid, repairs host-network drift, republishes dispatch metrics, restarts Hermes, and kicks unreachable port-forwards. It then compares health counts and writes a report under `~/.k3dm/orbstack-upgrade/`.

If preflight says the hub-data export is stale, run `make hub-data-export` and retry. Never use `deploy_vault` as an upgrade recovery step.
