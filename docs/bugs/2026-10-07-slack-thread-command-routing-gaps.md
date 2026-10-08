# Slack thread commands silently drop diagnostics and other registered commands

**Filed:** 2026-10-07
**Release / branch:** v1.42.0 / `k3d-manager-v1.42.0`
**Status:** REOPENED — routing added, but successful handlers emit a false Unknown command
**Severity:** Medium — read-only investigation commands disappear without feedback
**Component:** Slack Events API command dispatch

## Evidence and scope

Operator screenshot shows these replies with no visible acknowledgement:

```text
cluster-diagnose hub monitoring kube-prometheus-stack-grafana-7b66b4567f-sm4c4
cluster-diagnose hub monitoring pod kube-prometheus-stack-grafana-7b66b4567f-sm4c4
```

The second follows documented namespace-before-pod shorthand. The first needs usage feedback.
Source audited at `a7bff6228d65e5a9ee8ea851de2f8aad4d6e282d`; deployed revision and actual
Slack event receipt are unknown. Eight isolated calls of the extracted dispatcher confirm
silent early return for missing bare commands, without executing workers.
See [full audit evidence](../issues/2026-10-07-slack-thread-command-routing-audit.md).

## Root cause

`bin/k3dm-webhook` independently maintains `_THREAD_COMMANDS`, `_STANDALONE_CMDS`,
and `_handle_thread_command`. `cluster-diagnose` is missing from both sets and has no handler.
Matched threads enter the dispatcher, which returns early for unrecognized bare commands;
orphan threads and top-level messages never dispatch these commands.

| Command | Confirmed source result |
|---|---|
| cluster-diagnose | Registered slash command; no bare-message/thread route |
| k3dm | Registered slash command; no bare-message/thread route |
| argocd-upgrade | Registered slash command; no bare-message/thread route |
| hermes-auth | Relay-local authentication command; no thread route, parity requires explicit design |
| refresh | Standalone gate and handler exist, but thread gate rejects bare command |
| up, down, resume | Handler aliases exist, but bare thread and standalone gates reject them |

The other twelve registered slash commands have gates and handlers. That establishes routing
presence only, not end-to-end success or argument/authorization/delivery parity.
The prior [diagnostics delivery bug](2026-10-07-slack-cluster-diagnostics-not-threaded.md)
is FIXED and concerns worker output placement. This report is a separate input-routing gap.
The fixed [ask-docs follow-up bug](2026-10-01-ask-docs-thread-follow-up-silently-dropped.md)
had the same class of early-return failure.

## Expected behavior and acceptance

1. Support diagnostics bare replies in matched/orphan threads and top-level message events,
   using the slash parser's existing provider/namespace/verb validation and reader role floor.
2. Valid diagnostics queue exactly one worker and acknowledge/reply in the originating channel
   and thread. Malformed requests show usage without running a worker.
3. For k3dm and argocd-upgrade, explicitly implement parity or send a clear slash-only response.
   Do not silently ignore a recognized registered command.
4. Resolve alias policy consistently: support aliases with canonical authorization, or remove
   dead branches and document rejection. Normal conversation remains silently ignored.
5. Keep hermes-auth relay-local unless a reviewed authenticated design is supplied; never mint
   a session or bypass the existing authentication flow from an untrusted thread.
6. Add table-driven registry/handler/help coverage and event-level tests for matched/orphan
   threads, top-level messages, invalid arguments, roles, bot/subtype filtering, and duplicate
   delivery. Stub workers; do not run cluster lifecycle/cleanup/upgrade operations in tests.
7. Canonicalize aliases before role checks. Maintain per-target k3dm roles, Make allowlists,
   mutation confirmation semantics, and channel/thread correlation.

No runtime fix, live job submission, Slack message, or service restart was performed.

## Fix

The webhook now routes `cluster-diagnose`, `k3dm`, and `argocd-upgrade` from both
top-level Slack messages and existing/orphan threads. Child jobs inherit the originating
thread timestamp and channel, and ArgoCD upgrade jobs now publish a terminal result to Slack.
`hermes-auth` remains intentionally relay-local.

## 2026-10-08 regression triage: handled commands fall through

Operator screenshot shows `cluster-diagnose hub pods monitoring` acknowledged with job
`a41b5ddc`, then an Unknown command message, then the diagnostics result. The syntax is valid.
Source revision `fefb741070ff87418b181508a8589969f38dcec3` has the new handlers, but they
are followed by a separate `if cmd == "kill"` chain instead of continuing with `elif`.
A successful diagnostics, k3dm target, or ArgoCD upgrade branch therefore runs the second chain
and reaches its final unknown-command else. This directly reproduces both messages in one
handler invocation; duplicate servers are not required. Running deployment revision is unknown.

See [reproduction and evidence](../issues/2026-10-08-slack-thread-dispatch-fallthrough.md).
Three stubbed-worker probes queue exactly one worker and emit both queued and unknown-command;
`k3dm help` returns explicitly and is unaffected. Validation/rejection branches that return early
are also outside the successful-handler fallthrough path.

Follow-up: change the second chain's initial `if` to `elif`, or explicitly return after each
successful new handler. Test successful diagnostics, authorized k3dm target and upgrade commands
for one queue acknowledgement and zero unknown-command replies; retain help/error/role checks,
existing kill/status/logs behavior, and event-level thread/channel assertions. Stub workers and
assert absence of contradictory replies, not only that a worker was invoked. No runtime fix yet.
