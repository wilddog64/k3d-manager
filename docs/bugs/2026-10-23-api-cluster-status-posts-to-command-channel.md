# Bug: API-origin cluster status reports land in #acg-automation with the slash-command traffic

**Status:** LIVE-VERIFIED (promoted 2026-10-24; the live check below already passed) — was VERIFIED — LANDED `7016f6d0` 2026-10-23 — E1/E2 green (pytest 28, bats 12); 6 pytest tests and bats test 7 red on the pre-fix code. E3 FAILED 2026-10-23 19:55 PDT: with `K3DM_STATUS_CHANNEL_ID=C4CAEH8HX` set (plist confirmed, webhook restarted 19:54), cloud request `20261024T025455Z-cluster-status` (job `c4b35b3c`) could not start a thread in the status channel; `_post_status_report` returned False and `_notify_job` delivered it to the default channel `C0B7ZHG2LR4` (#acg-automation) via `bot_fallback`, as M-fallback specifies. Slack's error is discarded by `_post_slack_bot`, so the reason is unknown: bot not in the channel, wrong channel ID, or missing scope. Second attempt FAILED 2026-10-23 ~20:10 PDT: after the operator's channel/bot check and a webhook restart (20:05), job `28b9778a` again went `bot_fallback` to `C0B7ZHG2LR4` (`channel_id` null), with the ID unchanged at `C4CAEH8HX`. Pending: the operator confirms `C4CAEH8HX` is #grafana-notification's ID (channel About tab) and that the bot is listed under the channel's Integrations; a P3 to log Slack's error code is proposed. Third attempt (job `5f0c705e`, 20:25 PDT, after the logging fix `978b2414` and a restart) logged no Slack warning: the post was never attempted. Cause: `launchctl print` shows the loaded job has no `K3DM_STATUS_CHANNEL_ID`; `restart-webhook`'s `kickstart -k` never re-read the plist (`docs/bugs/2026-10-23-restart-webhook-kickstart-ignores-plist-env-changes.md`). Channel ID, bot membership and posting permissions all confirmed correct by the operator. E3 PASSED 2026-10-24 (04:19 PDT; time corrected from ~00:40 by the job's thread_ts mtime) after the operator reloaded the LaunchAgent (bootout + bootstrap): `launchctl print` shows `K3DM_STATUS_CHANNEL_ID => C4CAEH8HX`; job `ded5d015` wrote `thread_ts` and no `delivery.jsonl` (no fallback), and the webhook log has no `chat.postMessage` warning. Repeat 2026-10-24 05:50 PDT (job `35e0429d`): posted in #grafana-notification, confirmed by the operator's screenshot. Sidebar check 2026-10-24 06:06 PDT (job `1c53b7d4`, operator on #notes): #grafana-notification turned bold like #acg-automation. Earlier posts looked read because #grafana-notification was the open channel in Slack.
**Fix commit:** `7016f6d0`
**Priority:** P3
**Severity:** low — reports arrive, but in the command channel; alert-style status is mixed with operator commands
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude, after the operator asked: "is it possible send alert to granfan-notification instead of acg-automation"
**Approval:** explicit 2026-10-23. The operator said: "sounds good. file as you suggested, and dispatch after P2 and P3 completed and verified".
**Related:** `docs/bugs/2026-10-23-bare-tunnel-start-repoints-hostinger-tunnel.md`, `docs/bugs/2026-10-23-status-snapshot-age-missing-unit.md` (dispatch order only)

**Component:** `scripts/lib/webhook/status.py` (`_post_status_report`), `scripts/lib/webhook/config.py`, `bin/k3dm-webhook` (runtime wiring), `Makefile` (`update-webhook-slack`)

## Problem

The 18:15 and 18:16 PDT Hostinger FAIL posts on 2026-10-23 were not alerts. They came from
`/api/v1/cluster-status` requests sent through the cloud bridge (01:15:25Z and 01:16:05Z). Grafana
alerts already go to #grafana-notification through Alertmanager.

An API or cloud-request status job carries no `response_url`, no `channel_id` and no `thread_ts`.
`_post_status_report` returns False for that case, and each caller (`_run_cluster_status`,
`_run_hostinger_status`, `_run_cluster_diagnostics`) falls back to `_notify_job`, which posts to the
default `SLACK_CHANNEL_ID` (#acg-automation). There is no way to send these reports anywhere else.

## Fix

### F1. `K3DM_STATUS_CHANNEL_ID`

`scripts/lib/webhook/config.py`: `STATUS_CHANNEL_ID = os.environ.get("K3DM_STATUS_CHANNEL_ID", "")`.
`bin/k3dm-webhook` wires it into the status module the same way as `_slack_channel_id`
(`_status._status_channel_id = lambda: STATUS_CHANNEL_ID`; module default `lambda: ""`).

### F2. Route API-origin reports

In `_post_status_report`, when `response_url`, `channel_id` and `thread_ts` are all empty, a bot
token is set and `_status_channel_id()` is non-empty:

- start a thread in that channel with the header (`_start_bot_thread(header, channel_id=<status channel>)`),
  write `thread_ts` to the job dir, and post the body in the thread, as the existing bot path does;
- return True, so `_notify_job` does not also post to the default channel;
- if the thread start fails, return False, so the existing `_notify_job` fallback still delivers it.

Every other case is unchanged: a slash command still replies where it was typed (its
`response_url`, or the incoming thread), and an unset `K3DM_STATUS_CHANNEL_ID` keeps today's
behavior. The channel comes from the operator's own config, not the request, so this does not
loosen the rule in `_start_status_thread` that a request may not open a thread in another channel.
The request body must not be able to set the status channel.

This applies to all API-origin status jobs (cluster status, Hostinger status, diagnostics), not
only FAIL/WARN reports. A severity filter can come later if wanted.

### F3. Makefile

`update-webhook-slack`: if `K3DM_STATUS_CHANNEL_ID` is exported, write it into the plist's
`EnvironmentVariables`; if not, leave any existing value as it is. It is optional: its absence is
never an error.

### F4. Docs

`docs/howto/webhook-operations.md`: what `K3DM_STATUS_CHANNEL_ID` does, how to set it
(`K3DM_STATUS_CHANNEL_ID=<id> make update-webhook-slack`), and that the bot must be invited to that
channel first.

## Tests

`scripts/tests/bin/test_webhook_cluster_status_thread.py` (stub `_post_slack_bot`; no real Slack):

1. Status channel `CSTATUS` set, no `response_url`/`channel_id`/`thread_ts`: the header and body go
   to `CSTATUS` (thread start, then a threaded reply), and `_notify_job` is not called.
2. Same, but the status channel is unset: `_notify_job` is called, as today.
3. Status channel set, but the request has a `response_url`: the report goes to the `response_url`
   only; nothing goes to `CSTATUS`.
4. Status channel set, the request has an incoming `thread_ts` and `channel_id`: the reply goes to
   that thread, not to `CSTATUS`.
5. Status channel set, thread start fails: `_notify_job` delivers the report.
6. A request body field naming a channel (e.g. `status_channel_id`) has no effect.

`scripts/tests/bin/makefile_webhook_slack.bats` (temp `HOME`, stub `security` and `launchctl`, as
the suite does):

7. With `K3DM_STATUS_CHANNEL_ID` exported, the plist gains it; without it, an existing value is kept
   and a missing one is not added.

Show tests 1 and 7 red against the pre-fix code.

## Files

- `scripts/lib/webhook/status.py`
- `scripts/lib/webhook/config.py`
- `bin/k3dm-webhook`
- `Makefile`
- `scripts/tests/bin/test_webhook_cluster_status_thread.py`
- `scripts/tests/bin/makefile_webhook_slack.bats`
- `docs/howto/webhook-operations.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: With K3DM_STATUS_CHANNEL_ID set, a status job with no response_url, channel_id or thread_ts posts its report as a thread in that channel and not in the default channel.
  - id: M2
    text: If the thread cannot be started in the status channel, the report is still delivered through the existing default-channel fallback.
  - id: M3
    text: make update-webhook-slack writes K3DM_STATUS_CHANNEL_ID into the webhook plist when it is exported and keeps an existing value when it is not.
  - id: M4
    text: The webhook operations how-to documents the variable, how to set it and the bot invite.
must_not:
  - id: N1
    text: A slash-command status report (response_url or incoming thread present) must not go to the status channel.
  - id: N2
    text: With K3DM_STATUS_CHANNEL_ID unset, delivery must not change.
  - id: N3
    text: A request body must not be able to choose the status channel.
  - id: N4
    text: Tests must not call the real Slack API, read the real Keychain or write the real ~/Library/LaunchAgents.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2, N3, N4]
    text: pytest scripts/tests/bin/test_webhook_cluster_status_thread.py green; test 1 red on the pre-fix code.
  - id: E2
    kind: offline
    proves: [M3, N4]
    text: bats scripts/tests/bin/makefile_webhook_slack.bats green; test 7 red on the pre-fix Makefile.
  - id: E3
    kind: live
    proves: [M1, N1]
    text: After the operator invites the bot to #grafana-notification, runs K3DM_STATUS_CHANNEL_ID=<id> make update-webhook-slack, Claude sends one cloud-bridge cluster-status request and the operator confirms it in #grafana-notification; a /k3dm status slash command still replies in #acg-automation.
interface:
  - POST /api/v1/cluster-status (body provider, response_url, thread_ts, channel_id)
  - env K3DM_STATUS_CHANNEL_ID, SLACK_CHANNEL_ID, SLACK_BOT_TOKEN
  - make update-webhook-slack (~/Library/LaunchAgents/com.k3d-manager.webhook.plist)
```

## Definition of Done

- [ ] F1–F4 and a CHANGELOG `[Unreleased]` `### Added` entry; only the Files above change.
- [ ] `pytest scripts/tests/bin/test_webhook_cluster_status_thread.py` and `bats scripts/tests/bin/makefile_webhook_slack.bats` green; paste both summaries.
- [ ] Tests 1 and 7 shown red on a temp copy of the pre-fix code.
- [ ] Commit: `feat(webhook): send API-origin status reports to a configurable channel`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT call the real Slack API, read the real Keychain, or restart the real webhook from tests.
- Do NOT let a request body set or override the status channel.
- Do NOT change where slash-command replies go or relax `_start_status_thread`.
- Do NOT add a severity filter.
- Do NOT modify files outside the Files list.

**Live evidence:** 2026-10-24 · run job-ded5d015 · env hub · scenario api-status-report-in-status-channel · commit f916f44f · proves E3
