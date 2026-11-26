# Webhook operations

## Which channel

Route notices by who started them:

| Started by | Channel | Examples |
|---|---|---|
| The operator or an agent | `#acg-automation` (`SLACK_CHANNEL_ID`) | Slash commands, `/ask`, make and cluster jobs, their failure and stall analyses, and cloud-bridge task replies |
| The system | `#grafana-notification` (`K3DM_STATUS_CHANNEL_ID`) | Alert analyses, ACG expiry, scheduled credential rotations, CVE scan notices, and cluster-status reports |

Alert analyses from Alertmanager use this order: a supplied Slack `response_url` gets
the reply; otherwise, when the bot token and `K3DM_STATUS_CHANNEL_ID` are configured,
the webhook bot posts there. If that bot post fails or the status channel is unset, the
analysis falls back to `K3DM_SLACK_WEBHOOK_URL`.

To route scheduled ACG expiry and credential-rotation notices, create an Incoming
Webhook for `#grafana-notification` in the Slack app and replace the
`slack-incoming-webhook-url` value in the hub Secret
`platform-ops/platform-ops-notifications`. The CronJobs read that Secret on each run,
so they do not need a restart. The webhook URL is managed by the operator.

API-origin cluster status, Hostinger status and diagnostics reports can be posted as
threads in a dedicated Slack channel by setting `K3DM_STATUS_CHANNEL_ID`. Invite the
webhook bot to the channel first, then install the setting with:

```bash
K3DM_STATUS_CHANNEL_ID=<id> make update-webhook-slack
```

The setting applies to reports with no slash-command response URL or incoming thread;
slash-command replies continue in their originating conversation. When the variable is
not exported, `update-webhook-slack` preserves any existing plist value.
`make restart-webhook` reloads the LaunchAgent plist, so updated environment variables apply.

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

## Notification routes

Cloud sessions can route job notices for `make-*`, `sandbox-up`, and `sandbox-down`
requests to an approved Slack channel alias via `notify_route` / `--notify-route`.

- **Set the route map:** Store `alias:CHANNEL_ID,...` (at most 8 aliases, 512 bytes
  max, `default` reserved) in Keychain item `k3dm-slack-notification-routes`
  (account `k3dm`, listed in `scripts/etc/machine/secrets.hub.list`) or export
  `K3DM_SLACK_NOTIFICATION_ROUTES`:

  ```bash
  K3DM_SLACK_NOTIFICATION_ROUTES="testing:C0123456789" make update-webhook-slack-routes
  ```

  `make update-webhook-slack-routes` validates the map, saves it to Keychain, and
  runs `make restart-webhook`, which restarts both `k3dm-webhook` and
  `k3dm-cloud-bridge`.
- **Check the configuration:** Run `bin/k3dm-webhook-doctor --check` and inspect
  the `slack_notification_routes` field (`configured`, `absent`, or `invalid`).
- **Channel membership:** Public channels need no invite: the bot token has
  `chat:write.public` (captured 2026-11-26, see
  [`v1.46.0-p2b-webhook-notify-route.md`](../plans/v1.46.0-p2b-webhook-notify-route.md)).
  For a private channel, invite the bot first; otherwise Slack answers
  `channel_not_found` and the job's notices are recorded as undelivered.
- **Low-audience rule and accepted risk:** Only alias low-audience channels
  (never incident or announcement channels). Anyone who can push to
  `cloud-requests` can route an ungated action (such as `make-test-all`) without
  operator approval; limiting aliases to low-audience channels contains that risk.
- **No-spill behaviour:** A routed job's notices stay in the aliased channel and
  never fall back to `SLACK_CHANNEL_ID` or `SLACK_WEBHOOK_URL`. If Slack refuses
  delivery (for example, a private channel the bot is not in, or an archived or wrong ID), the webhook records
  `"delivered": false` in that job's `delivery.jsonl` and does not send the
  notice elsewhere.
