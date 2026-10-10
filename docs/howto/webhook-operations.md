# Webhook operations

`k3dm-webhook` and `k3dm-cloud-bridge` write structured UTC log lines to their
LaunchAgent log. The default `K3DM_LOG_LEVEL=info` records requests and job
boundaries. Set `K3DM_LOG_LEVEL=debug` when investigating a job; `warn` and
`error` reduce routine detail.

The installed agents can be updated together with:

```bash
make webhook-log-level LEVEL=debug
```

The webhook and cloud bridge LaunchAgents use the pinned Homebrew interpreter
`/opt/homebrew/opt/python@3.14/bin/python3.14`, not the unversioned `/opt/homebrew/bin/python3`.
If an installer reports that Python is missing, run `brew install python@3.14` before rendering
or loading either plist.

The helper edits both LaunchAgent plists and restarts the agents. It does not
log request bodies, headers, bearer tokens, Keychain values, Slack response
URLs, or make output. Status routes are logged as `/api/v1/status/{job_id}`.

Job logs and cleanup retention are described here as the v1.41.0 rollout
lands; use the job ID from the webhook response when inspecting a job. Make
jobs stream their local output to `make.log`, capped at the last 1 MiB when
the job finishes. Inspect it with `make job-log ID=<job_id>`; this file is not
the `output` returned by the cloud bridge.

The daily cleanup agent removes finished job folders older than 14 days and
keeps at most 500 finished folders. It never removes `running` or `queued`
jobs. LaunchAgent files named `k3dm-*.log` over 10 MiB are rotated in place,
with five compressed generations retained.

Failed jobs also leave a short redacted `failure.md`. Run
`make harvest-job-failures` to copy waiting notes into `docs/job-failures/` for
review and commit; repeated signatures become recurrence entries, and
harvested folders are marked so reruns are no-ops.
