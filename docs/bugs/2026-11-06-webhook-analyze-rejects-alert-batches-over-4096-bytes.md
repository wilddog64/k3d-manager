# Bug: webhook analyze rejects Alertmanager batches over 4,096 bytes, dropping them

**Status:** OPEN — observed 2026-11-06 on the M5; last rejection 2026-11-01T21:52Z
**Priority:** P2
**Approval:** pending
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-06-webhook-analyze-reports-success-when-slack-post-fails.md`

## Symptom

`alertmanager_notifications_failed_total{integration="webhook",reason="clientError"}` is 24 of 57 attempts in the current Alertmanager pod (up 6d17h). Its log, sampled 2026-11-01 13:52Z to 21:52Z, shows:

    cicd/k3dm-analyze/k3dm-analyze/webhook[0]: notify retry canceled due to unrecoverable error after 1 attempts:
    unexpected status code 413: https://webhook.3ai-talk.org/api/v1/analyze

All 24 error lines in 168 hours are level=error. The sampled lines carry `num_alerts=2`.

## Cause

`MAX_BODY = 4096` in `scripts/lib/webhook/config.py`, enforced before the route at `bin/k3dm-webhook:2365`. An Alertmanager v4 payload repeats labels and annotations per alert plus common labels, so two Trivy alerts can exceed it. A 413 is unrecoverable to Alertmanager, so the batch is dropped until the next repeat, which is rejected too.

Not confirmed: whether the batch that stopped failing after Nov 1 shrank by chance. Requests since are 202, so this can return whenever a batch grows.

## Files

- `bin/k3dm-webhook`
- `scripts/lib/webhook/config.py`
- `scripts/tests/bin/test_webhook_analyze_routing.py`

## Fix direction

Give `/api/v1/analyze` and `/api/v1/cve-remediate` their own bounded limit, sized from a real captured payload, as `SLACK_EVENT_MAX_BODY` does for Slack events. Keep the auth check ahead of reading the body, and keep 4,096 on every other route.

## Acceptance

```yaml
must:
  - id: M1
    text: "An authenticated POST to /api/v1/analyze with a real multi-alert Alertmanager payload over 4096 bytes is accepted with 202."
must_not:
  - id: N1
    text: "A body over the new analyze limit is still refused with 413 (paired with M1)."
  - id: N2
    text: "Other routes keep the 4096 byte limit (paired with M1)."
  - id: N3
    text: "An unauthenticated large body is not accepted."
evidence:
  - {id: E1, proves: [M1, N1, N2, N3], kind: offline, text: "Test against a local server with a payload captured from the hub Alertmanager, host and date recorded; M1 red on the pre-fix commit; each must_not red by a mutant."}
  - {id: E2, proves: [M1], kind: live, text: "alertmanager_notifications_failed_total clientError stops increasing while a multi-alert group fires."}
interface:
  - "POST /api/v1/analyze"
  - "POST /api/v1/cve-remediate"
```
