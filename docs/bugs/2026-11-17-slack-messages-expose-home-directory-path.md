# Slack messages expose the operator's home directory path

**Status:** OPEN — stall-watch notice fixed (shows `~/`); other Slack senders not yet audited
**Priority:** P3
**Introduced by:** pre-existing (stall-watch notice since the dispatch stall detector, v1.44.1)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** not run (vector store unreachable: context `k3d-k3d-cluster` does not exist; exact-slug glob found none)

## Report

Operator, 2026-11-17 (Slack screenshot, 19:16): "message sent to slack should not expose user info. use ~/ in stead".
The stall notice read `evidence /Users/<user>/.local/share/k3d-manager/worktrees/v1.44.1/e8-toy-stall.run/stall-…`.

## Done

`bin/k3dm-dispatch-stall-watch` `_watch_capture` writes the evidence path with `$HOME` replaced by `~` (bash 3.2 and 5
checked). Test `S1` in `scripts/tests/bin/dispatch_stall_watch.bats` fails on the old code and passes now.

## Open

Other Slack senders were not audited: `bin/k3dm-hermes`, `bin/k3dm-slack-notify`, `bin/k3dm-webhook`, `bin/k3dm-sandbox-reaper`,
`scripts/lib/webhook/render.py` and the rest of `scripts/lib/webhook/`. Option: one filter in the shared send path
(`k3dm-slack-notify` and the webhook's post helper) that replaces `$HOME` with `~` in every message.

## Live observation (2026-11-17)

A real stall notice at 10:21 PST (18:21Z, slug `vault-unseal-secret-follows-keychain-restore`, 48 min after d2a72d35 landed at 09:33 PST) read `evidence ~/.local/share/k3d-manager/worktrees/v1.44.2/vault-unseal-secret-follows-keychain-restore.run/stall-20261117T182150Z`: the stall-watch part works live (operator screenshot, 2026-11-18). The other Slack senders are still unaudited, so the doc stays OPEN.
