# Webhook operations

`k3dm-webhook` and `k3dm-cloud-bridge` write structured UTC log lines to their
LaunchAgent log. The default `K3DM_LOG_LEVEL=info` records requests and job
boundaries. Set `K3DM_LOG_LEVEL=debug` when investigating a job; `warn` and
`error` reduce routine detail.

The installed agents can be updated together with:

```bash
make webhook-log-level LEVEL=debug
```

The helper edits both LaunchAgent plists and restarts the agents. It does not
log request bodies, headers, bearer tokens, Keychain values, Slack response
URLs, or make output. Status routes are logged as `/api/v1/status/{job_id}`.

Job logs and cleanup retention are described here as the v1.41.0 rollout
lands; use the job ID from the webhook response when inspecting a job.
