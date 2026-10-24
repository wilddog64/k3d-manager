# Bug: `make restart-webhook` keeps launchd's cached environment, so `update-webhook-slack` changes never reach the webhook

**Status:** DISPATCHED — 2026-10-24
**Priority:** P2
**Severity:** medium — a plist environment change is silently inert; the status channel never took effect
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude, while chasing status-channel E3
**Approval:** explicit 2026-10-23. The operator said: "go ahead" (dispatch go; critical: restarts the webhook's launchd job).
**Related:** `docs/bugs/2026-10-23-api-cluster-status-posts-to-command-channel.md`,
`docs/bugs/2026-10-23-slack-bot-post-discards-slack-error.md`,
`docs/bugs/2026-10-01-restart-webhook-leaves-cloud-bridge-on-stale-code.md`

**Component:** `Makefile` (`restart-webhook`, `update-webhook-slack`)

## Problem

`update-webhook-slack` rewrites `~/Library/LaunchAgents/com.k3d-manager.webhook.plist` and then
runs `restart-webhook`. `restart-webhook` uses `launchctl kickstart -k`, which restarts the job
definition launchd loaded at bootstrap. It does not re-read the plist, so new or changed
`EnvironmentVariables` never reach the process. It falls back to `bootout` + `bootstrap` only when
kickstart fails.

Evidence, 2026-10-23 20:25 PDT: the plist file has `K3DM_STATUS_CHANNEL_ID=C4CAEH8HX`;
`launchctl print gui/<uid>/com.k3d-manager.webhook` lists `SLACK_CHANNEL_ID` but no
`K3DM_STATUS_CHANNEL_ID`. With the Slack-error logging landed (`978b2414`), job `5f0c705e` logged no
`chat.postMessage` warning and went `bot_fallback`, so the webhook never attempted the status
channel: `_status_channel_id()` was empty. Three E3 attempts (jobs `c4b35b3c`, `28b9778a`,
`5f0c705e`) failed for this reason, not because of Slack.

## Fix

### F1. Reload the definition on restart

`restart-webhook` runs `launchctl bootout gui/<uid>/com.k3d-manager.webhook` (ignore "not loaded")
then `launchctl bootstrap gui/<uid> <plist>`, instead of `kickstart -k`. Keep the existing
`restart-cloud-bridge` call. If `bootstrap` fails with the transient I/O error handled in
`docs/bugs/2026-09-16-restart-webhook-bootstrap-io-error.md`, keep that bug's retry.

### F2. Say so

After the restart, `restart-webhook` prints `[restart-webhook] reloaded LaunchAgent definition`.

## Tests

`scripts/tests/bin/restart_webhook.bats` (new, or the existing restart-webhook suite if one exists;
stub `launchctl` on `PATH` recording its arguments, temp `HOME`):

1. `make restart-webhook` calls `launchctl bootout` then `launchctl bootstrap` with the plist path, and never `kickstart`.
2. `bootout` failing (job not loaded) still leads to `bootstrap`, and the target exits 0.
3. `restart-cloud-bridge` still runs.

Show test 1 red against the pre-fix Makefile.

## Files

- `Makefile`
- `scripts/tests/bin/restart_webhook.bats` (or the existing suite that covers `restart-webhook`)
- `docs/howto/webhook-operations.md` (one line: restart reloads the plist, so env changes apply)
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: make restart-webhook reloads the LaunchAgent definition from the plist (bootout then bootstrap), so EnvironmentVariables changes reach the new process.
  - id: M2
    text: restart-webhook succeeds when the job is not loaded, and still restarts the cloud bridge.
must_not:
  - id: N1
    text: restart-webhook must not use launchctl kickstart for the webhook.
  - id: N2
    text: Tests must not call the real launchctl or touch the real ~/Library/LaunchAgents.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2]
    text: bats restart-webhook suite green; test 1 red on the pre-fix Makefile.
  - id: E2
    kind: live
    proves: [M1]
    text: After the operator runs make restart-webhook, Claude confirms launchctl print shows K3DM_STATUS_CHANNEL_ID, files a cluster-status cloud request, and the report lands in the status channel (thread_ts written, no delivery.jsonl).
interface:
  - make restart-webhook
  - launchctl bootout / bootstrap gui/<uid>/com.k3d-manager.webhook
```

## Definition of Done

- [ ] F1, F2, the how-to line and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] The bats suite green; paste the summary.
- [ ] Test 1 shown red on a temp copy of the pre-fix Makefile.
- [ ] Commit: `fix(webhook): reload the LaunchAgent definition on restart-webhook`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT run the real `launchctl`, restart the real webhook, or read the plist's secret values.
- Do NOT modify files outside the Files list.
