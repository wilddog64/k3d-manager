# Bug: Slack slash-command manifest is out of sync with relay code

**Status:** CLOSED — doc merged to main in PR #102; no open follow-up was found. Not individually re-verified; reopen with a Recurrence section if it is seen again (2026-10-09 status sweep)
**Filed:** 2026-07-01
**Source:** /ask agent observation

## Description

`workers/slack-relay/index.js` allows `/cluster-status` and `/hostinger-status`, but `docs/howto/slack-slash-commands.md` only lists `/acg-up`, `/acg-down`, `/acg-status`, `/acg-resume`, `/claude`, `/gemini`, `/codex`, and `/argocd-upgrade`. That mismatch is a real configuration risk and directly explains a silent non-response if the Slack app was provisioned from the documented manifest.

## Resolution

The manifest snippet in `docs/howto/slack-slash-commands.md` now matches the relay command set, including `/cluster-status`, `/cluster-refresh`, `/cluster-resume`, and `/hostinger-status`.
