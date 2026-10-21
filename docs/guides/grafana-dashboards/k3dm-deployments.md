# k3dm Deployment Metrics (`k3dm-deployments`) — ACG only

[← Grafana dashboards index](../grafana-dashboards.md)

CLI runs publish to the hub Pushgateway under `job="k3dm-cli"`; webhook runs keep
`job="k3dm-webhook"`. Set `K3DM_DEPLOYMENT_METRICS=0` to disable the CLI push. The panels
query the `prometheus` datasource uid.

| Panel | Query |
|---|---|
| Last acg-up / acg-down Duration | `max by (provider, status) (k3dm_deployment_duration_seconds{action="up"\|"down"})` |
| Last Deployment Success | `max by (action, provider) (k3dm_deployment_success)` |
| Last Deployment Time | `max by (action, provider) (k3dm_deployment_last_timestamp_seconds) * 1000` |
| Deployment Duration Over Time | `max by (action, provider, status) (k3dm_deployment_duration_seconds)` |

> **Every panel aggregates `job_id` away, and must keep doing so.** `_push_metrics()` stamps
> `k3dm_deployment_duration_seconds` and `k3dm_deployment_success` with the job's own
> `job_id`, so querying either metric bare returns one series *per deployment in the
> dashboard window*. The stat panels rendered a separate tile for each — fifteen
> identically-labelled `aws (failed) 0 s` tiles at one point — and the time series legend
> repeated `up/aws (failed)` once per job. `k3dm_deployment_last_timestamp_seconds` carries
> no `job_id` and so was never affected, which is why that one panel stayed readable while
> the others did not. `scripts/tests/plugins/observability_deployment_dashboard.bats` asserts
> all five queries stay aggregated.

> **The panel titles say `acg-up` / `acg-down`, which are the pre-v1.7.1 script names**
> (now `bin/cluster-up` / `bin/cluster-down`). The titles are literal strings in
> `k3dm-deployments-configmap.yaml`, so the table above quotes the dashboard as deployed.
> Renaming them means editing the ConfigMap and reapplying `make observability-acg`.

Fed by `k3dm-webhook`'s `_push_metrics()` → Pushgateway, and this is the **only** dashboard
whose producer is a push, not a scrape. The chain has three host-side links that each fail
independently: the webhook LaunchAgent, the Pushgateway port-forward LaunchAgent on
`localhost:9091` (Hostinger's forward, rewritten by `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`;
a sandbox `bin/cluster-up` Step 14c installs its own on `localhost:9092`), and the Pushgateway pod itself.

**The hub has no Pushgateway** — the webhook pushes only for the ACG provider. This
dashboard being empty on the hub is by design, not a regression. See
`docs/architecture/cloudflare-slack-relay.md` §3 for the full metrics path.

**A deployment series with `duration == 0` was never a deployment.** Until v1.39.0
`scripts/tests/lib/webhook.bats` isolated the port, token, `HOME`, `PATH`, `K3DM_JOB_DIR`
and `K3DM_RUN_DIR` but not `K3DM_PUSHGATEWAY_URL`, which `scripts/lib/webhook/config.py`
defaults to `http://localhost:9091` — the live forward on a dev host. Every `make test` run
therefore pushed three fabricated `up-gcp` / `up-aws` / `down-aws` groups from the suite's
own `/api/v1/cluster` cases, each with `duration_seconds 0` because the harness stubs `make`
to `exit 0`. The consequence was worse than three odd rows: `DeploymentMetricsStale` was
watching the test suite's last run rather than a deployment, so it could never fire while
the suite ran regularly. The harness now exports an empty `K3DM_PUSHGATEWAY_URL`, which
takes the `if not PUSHGATEWAY_URL: return` early exit in `_push_metrics()`. If you are
reading pre-v1.39.0 data, treat any zero-duration group as test exhaust and delete it:
`curl -X DELETE http://localhost:9091/metrics/job/k3dm-webhook/instance/<action>-<provider>`.
