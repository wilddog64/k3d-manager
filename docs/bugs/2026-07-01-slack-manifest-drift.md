# Bug: Slack manifest drift

**Filed:** 2026-07-01
**Source:** /ask agent observation

## Description

`workers/slack-relay/index.js` explicitly allows `/cluster-status` and relays it to `/api/v1/cluster-status`, and `bin/k3dm-webhook` has a matching `/api/v1/cluster-status` handler. But `docs/howto/slack-slash-commands.md` still shows a Slack manifest with only `/acg-up`, `/acg-down`, `/acg-status`, and `/acg-resume`, plus agent commands. That documented mismatch is a concrete cause of Slack not responding to `/cluster-status` if the app was provisioned from the docs.

## Resolution

`docs/howto/slack-slash-commands.md` now lists the current `/cluster-*` and `/hostinger-status` commands, and `scripts/tests/plugins/slack_slash_commands.bats` guards the manifest against future drift.
