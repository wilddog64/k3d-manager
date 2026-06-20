# Issue: cluster-up cannot be invoked as a top-level Slack command

**Date:** 2026-06-15
**Component:** bin/k3dm-webhook (Slack events handler)
**Status:** Filed — fix spec written: `docs/bugs/v1.7.1-bugfix-webhook-cluster-dispatch.md` (consolidated with the hostinger-misroute issue)

## Symptom

A user posting `/cluster-up <provider>` (or `cluster-up …`) as a top-level
Slack message in the configured channel sees no response from the webhook.
The command only works when posted as a reply inside an existing job thread.

## Investigation

`bin/k3dm-webhook` defines two command sets:

- `_THREAD_COMMANDS` (line ~548) — includes `cluster-up`, `cluster-down`,
  `cluster-refresh`, `cluster-resume`, etc.
- `_STANDALONE_CMDS` (line ~553) —
  `{"cluster-status", "hostinger-status", "cluster-refresh", "refresh",
    "ask", "claude", "gemini", "codex"}`

The `/slack/events` handler (lines ~2495–2538) routes incoming Slack
messages two ways:

1. Thread reply with a known `job_id` → `_handle_thread_command`.
2. Top-level message or orphan thread → only dispatched if `cmd in
   _STANDALONE_CMDS`.

Because `cluster-up` (and `cluster-down`) are missing from
`_STANDALONE_CMDS`, any top-level `cluster-up …` message falls through
the `if/elif` chain and is silently dropped. The dispatcher in
`_handle_thread_command` (line 717) is wired correctly — it just never
gets called for a fresh top-level invocation.

This is also why the unknown-command help text at line 797 lists
`cluster-up` and `cluster-down` — the dispatcher accepts them, but the
event router never delivers them from a top-level post.

## Root Cause

`cluster-up` and `cluster-down` were added to `_THREAD_COMMANDS` and to
the `_handle_thread_command` dispatcher, but never added to
`_STANDALONE_CMDS`. The Slack events handler therefore refuses to start
a new job from a top-level post.

## Fix Applied

None — bug filed. Proposed fix (for a follow-up spec, Codex handoff):

- Add `"cluster-up"`, `"cluster-down"`, `"cluster-resume"` to
  `_STANDALONE_CMDS` in `bin/k3dm-webhook`.
- Add a BATS or unit-style test covering the routing branch.
- Restart the webhook with `make restart-webhook` after the change.

## Notes

- Related: `docs/issues/2026-06-15-cluster-up-hostinger-routes-to-k3s-aws.md`
  (default provider + hostinger wiring gap in the same dispatcher).
- File: `/Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-webhook`
  lines 548–556, 717–737, 2495–2538.
- The `lib/` subtree rule does not apply — `bin/k3dm-webhook` is owned
  by k3d-manager.
