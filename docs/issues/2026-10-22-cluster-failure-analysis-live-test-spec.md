# Spec: safe live test for lifecycle failure-analysis Slack threading

**Status:** Proposed; documentation/spec only. No test command or runtime behavior is implemented by this change.
**Related bug:** `docs/bugs/2026-10-15-cluster-up-progress-slack-thread-missing.md`
**Current fix:** `85722ce3` is VERIFIED offline. This spec addresses only the missing safe way to exercise the notification path in live Slack; it does not reopen or replace the fix.

## Problem

The real `_run_cluster` failure path in `scripts/lib/webhook/lifecycle.py` sends a failure-analysis notification and then, for `up`, starts `_run_cleanup`. That cleanup can terminate `autossh` processes and delete the `ubuntu-k3s` kube context. Intentionally causing a real lifecycle failure is therefore not a safe live-verification procedure.

The existing tests safely simulate a failed lifecycle worker with stubbed Slack delivery, but that does not verify the deployed Slack integration or rendered placement. No current operator command is documented as a safe live trigger.

## Proposed behavior

Add a deliberately named, operator-only Slack test command, for example `/k3dm test-lifecycle-failure-notice`, that emits a synthetic failure-analysis notification using the current Slack request's delivery context. It must exercise the production notification helper and job/thread metadata handling, but must not invoke the real cluster lifecycle worker.

The synthetic flow should create a clearly labeled test job and send a small deterministic failure-analysis body containing that job ID. It should use the request's normal Slack response context so the operator can check the result in the conversation where the command was issued. If the context cannot be safely correlated, fail closed with an explicit response; do not send to the configured default channel.

## Safety requirements

- The command is gated by an explicit feature flag that is disabled by default, and remains restricted to the existing operator authorization policy.
- The command is a notification-only path. It must not call `_run_cluster`, `_run_cleanup`, `make`, SSH, `kubectl`, AWS APIs, or any provisioning/deprovisioning helper.
- It must not accept arbitrary shell text, provider arguments, channel IDs, response URLs, or thread timestamps from user input. Context is taken only from the verified Slack event/request.
- The synthetic message is unmistakably labeled as a test and carries a unique job ID; it must not claim a real cluster failed or that real failure analysis was run.
- It must not print or persist the raw response URL, Slack token, or unredacted request body. Retained delivery diagnostics use existing safe fields and redacted reason codes.
- Disable the feature flag after the live check. No automatic periodic messages, hidden fallback, or production lifecycle side effect is permitted.

## Acceptance criteria

1. With the feature flag disabled, the command is rejected and no job/notification is created.
2. With the flag enabled, a non-operator is rejected; an authorized operator receives a clearly labeled synthetic failure-analysis notice with a job ID in the originating Slack conversation/thread.
3. The test route runs the same notification helper and context persistence path used by lifecycle notifications, while never entering `_run_cluster` or `_run_cleanup`.
4. A deterministic unit test simulates a rejected first response-URL delivery followed by another notification. It proves that no unrelated default-channel bot post is made or saved as the job's parent thread. This test must not depend on live Slack failure injection.
5. Regression tests prove the feature-flag and authorization gates, redaction, job correlation, and absence of lifecycle side effects.
6. Live verification records the exact test job ID and a screenshot or equivalent Slack metadata showing the synthetic notice in the originating conversation/thread. The bug stays VERIFIED (not LIVE-VERIFIED) if placement cannot be established.
7. The feature flag is disabled again after verification and that state is confirmed without exposing secret values.

## Scope

If implementation is separately authorized, keep changes limited to:

- `bin/k3dm-webhook` — explicit gated test-command routing and safe synthetic notification orchestration;
- `scripts/lib/webhook/lifecycle.py` only if a small shared notification-only helper is required; do not modify real cleanup behavior;
- `scripts/tests/bin/test_webhook_thread_dispatch.py` — deterministic routing, feature-gate, authorization, redaction, and no-lifecycle-side-effect coverage;
- this spec and the related canonical bug's verification notes.

No release plan file is proposed. This spec does not itself authorize implementation, deployment, or a live test; those require a separate operator-approved implementation dispatch and an explicitly enabled test window.

## Verification gates for a future implementation

- Focused pytest for thread dispatch plus the relevant webhook BATS suite.
- Python AST/syntax check, `git diff --check`, `_agent_lint`, and `_agent_audit`.
- Review that the feature defaults off and the test route cannot call any cluster/cleanup operation.
- Live Slack test only after the implementation is landed and the operator explicitly enables the flag; disable it immediately after the evidence is collected.
