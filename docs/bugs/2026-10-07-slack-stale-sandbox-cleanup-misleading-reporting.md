# Slack stale sandbox cleanup help and completion reporting are misleading

**Status:** FIXED in branch; live Slack verification pending
**Filed:** 2026-10-07
**Affected release:** v1.42.0
**Verified revision:** 83ff7991a4468bc431fc7b29cae105d7c6ab9eef (cleanup behavior); follow-up thread handoff fix pending
**Source:** Operator Slack command and screenshot

## Operator evidence

Operator explicitly entered cleanup-stale-sandbox apply. The Slack response in
image(20261007-174350).png showed:

```text
Stale ACG sandbox cleanup (provider=k3s-aws, context=ubuntu-k3s)
  - stop launchd agents: com.k3d-manager.frontend-port-forward com.k3d-manager.pushgateway-port-forward
  - remove kube context: ubuntu-k3s
Cleanup complete: stale sandbox agents stopped and context removed.
```

The apply argument intentionally requests mutation. This incident is not evidence that
a bare preview command applied changes. The screenshot is a completion response, not
an error, and does not establish whether either resource operation actually failed.

## Confirmed help defects

workers/slack-relay/index.js defines:

```text
Usage: /cleanup-stale-sandbox [confirm]
Example: /cleanup-stale-sandbox confirm
Without `confirm`, the command previews changes only.
```

The same parser accepts both confirm and apply as mutation requests. The statement
"Without confirm ... previews" is therefore false for the supported apply alias.

Help does not explain that this is local ACG connection-state cleanup: stop two launchd
port-forward agents, remove their plist files, and delete the kubeconfig context.
It does not terminate an AWS/ACG sandbox, delete CloudFormation, or remove Kubernetes
workloads. Explain this scope and the admin requirement before the operator runs it.

## Confirmed result-reporting defects

bin/cleanup-stale-sandbox suppresses errors from launchctl bootout and kubectl config
delete-context using redirected stderr and || true, then prints a blanket completion
claim. Missing resources may legitimately be idempotent success, but permission,
configuration, tool, and service failures are indistinguishable from successful cleanup.

Correction: rm -f is not guarded by || true; with set -e, its failure aborts the script.
It must not be described as an ignored failure.

bin/k3dm-webhook._run_stale_sandbox_cleanup receives only captured output and a timeout
flag and sends the same ordinary cleanup notification for every non-timeout result.
It does not explicitly classify or propagate a nonzero cleanup exit code. The endpoint
initializes a queued job, but this worker does not write its terminal status/output.

## Acceptance criteria

- Show separate preview and apply examples. Document confirm and apply consistently.
  Do not claim all invocations lacking confirm are previews.
- Explain the exact local-only scope and admin role; distinguish sandbox teardown.
- Report each agent/plist/context as removed/stopped, already absent, or failed.
- Treat already-absent resources idempotently while preserving safe diagnostics for real failures.
- Return a nonzero result for incomplete cleanup; report partial failure truthfully in Slack.
- Persist terminal job status and bounded redacted output/exit evidence so status/log
  retrieval does not leave a completed cleanup permanently queued.
- Preserve preview semantics with no mutation, and ensure explicit request mode controls
  webhook execution rather than an inherited CONFIRM environment value.
  Inherited CONFIRM overriding preview is a code-path risk, not observed in this operator run.
- Add isolated command-stub coverage for preview, confirm/apply, already-absent resources,
  permission/tool failure, partial cleanup, timeout, and terminal job status.
- Operator verifies help plus preview/apply output after deployment.

## Validation and scope

Compared the operator evidence with current relay, executable, and webhook source.
No cleanup was run by this agent and no local/remote resources were changed.
Implemented the runtime fix on `k3d-manager-v1.42.0`: preview/apply help is now truthful,
cleanup reports per-resource outcomes and returns nonzero on incomplete work, and the webhook
persists terminal status, exit code, and bounded redacted output. Focused cleanup tests pass 4/4,
webhook lifecycle tests pass 8/8, and Slack relay tests pass 36/36. Live Slack verification
remains pending.

Follow-up investigation found one remaining routing gap: the thread-command dispatcher
started `_run_stale_sandbox_cleanup` without passing the originating Slack `channel_id`.
The worker could therefore lose the channel context needed for creating or replying to the
cleanup thread. The fix passes that value through and adds regression coverage; live Slack
verification remains pending.
Repository path/title dedup found no equivalent report. Search verification follows publication.
