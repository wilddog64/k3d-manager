# Bug: webhook analyze reports success when its Slack post fails

**Status:** OPEN — cause of the missing posts found 2026-11-06: the M5 plist has no route; the silent success is still in the code
**Priority:** P2
**Approval:** operator, 2026-11-06: "dispatch them in a batch base on dependencies or priority"
**Depends on:** `2026-11-06-webhook-analyze-rejects-alert-batches-over-4096-bytes` (same files; land it first)
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-06-webhook-analyze-rejects-alert-batches-over-4096-bytes.md`; `docs/bugs/2026-10-24-platform-ops-notifications-slack-url-lost-on-hub-rebuild.md`

## Symptom

The operator's `#grafana-notification` has no analyzer post after 2026-10-30/31, and none since a Nov 1 job thread. Yet the M5 webhook log shows `POST /api/v1/analyze status=202` every 12 hours, latest 2026-11-06T12:33:30Z, and job `f33c33d7` (11-06 04:33 PST) has status `success` with a full written analysis of `TrivyCriticalVulnerabilityDetected` for `wilddog64/shopping-cart-payment`.

The log line for a failed notice, `slack notification failed`, does not appear for these jobs.

## Cause

In `_run_analyze` (`bin/k3dm-webhook`), neither failure is seen:

    posted = _post_slack_bot(message, channel_id=STATUS_CHANNEL_ID)
    if not posted and SLACK_WEBHOOK_URL:
        _slack_post(SLACK_WEBHOOK_URL, message)
    ...
    _finish("success")

`_slack_post` returns False on any exception (`scripts/lib/webhook/render.py`), the return is discarded, and nothing handles neither path being configured. So a job can be `success` with no delivery.

On the M5 the case is exactly that one: the webhook plist has neither `K3DM_STATUS_CHANNEL_ID` nor `K3DM_SLACK_WEBHOOK_URL`, so no post was attempted, which is why no failure line appears. The missing setting is tracked in `docs/bugs/2026-10-31-hub-migration-drops-webhook-slack-bot-config.md`. This bug keeps the part that hid it.

## Files

- `bin/k3dm-webhook`
- `scripts/lib/webhook/render.py`
- `scripts/tests/bin/test_webhook_analyze_routing.py`

## Fix direction

Record delivery in the job: a job whose analysis could not be posted logs `slack notification failed` with the route and reason, and ends with a distinct status. Never log the URL or token.

## Decisions (Claude, 2026-11-06)

- The distinct status is `delivery_failed`. Find every reader of job status (`/api/v1/status`, metrics, Slack reply paths) and confirm it handles the new value; list them in your report.
- `_post_slack_bot` and `_slack_post` must both report their result to `_run_analyze`. Apply this only to the analyze path.

Dispatch order: land `2026-11-06-webhook-analyze-rejects-alert-batches-over-4096-bytes` first; both edit `bin/k3dm-webhook` and the same test file.

## Acceptance

```yaml
must:
  - id: M1
    text: "When no route is configured, or the Slack post fails on every configured route, the analyze job does not end with status success, and the webhook log records the failure with route and reason."
  - id: M2
    text: "When the post succeeds, the job ends with status success."
must_not:
  - id: N1
    text: "A failure to post does not lose the written analysis: the job output still holds it (paired with M1)."
  - id: N2
    text: "No log line or job file contains the webhook URL or bot token."
evidence:
  - {id: E1, proves: [M1, M2, N1, N2], kind: offline, text: "Test with a local stub Slack endpoint returning success and failure; M1 red on the pre-fix commit; each must_not red by a mutant."}
  - {id: E2, proves: [M2], kind: live, text: "The next analyze job on the M5 is success and its post is visible in Slack, confirmed by the operator."}
interface:
  - "POST /api/v1/analyze"
  - "job directory files: status, output"
  - "env: K3DM_JOB_DIR, K3DM_SLACK_WEBHOOK_URL, SLACK_BOT_TOKEN, K3DM_STATUS_CHANNEL_ID"
```
