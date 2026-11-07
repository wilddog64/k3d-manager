# Bug: the analyzer makes one LLM call and one Slack post for every firing alert, with no cap

**Status:** VERIFIED — restated 2026-11-07 by Claude, verification already recorded below; was: LANDED `62742959`, independent verify PASS 2026-11-06 (M1 to M4, N1, N2 over all four delivery routes; 6 mutants red). The HTTP route was not exercised offline. Live E2 open, after the M5 webhook restart
**Priority:** P2
**Severity:** medium. A large batch spends LLM quota and floods `#grafana-notification`. Nothing is lost.
**Approval:** not required: non-critical, Claude files and dispatches. Operator told 2026-11-06.
**Filed:** 2026-11-06
**Detected by:** Claude, reviewing `9691bbaa`
**Branch:** `k3d-manager-v1.43.14`
**Depends on:** `docs/bugs/2026-11-06-webhook-analyze-reports-success-when-slack-post-fails.md` (edits the same loop; dispatch after it lands)
**Related:** `docs/bugs/2026-11-06-webhook-analyze-rejects-alert-batches-over-4096-bytes.md`

## Problem

`_run_analyze` in `bin/k3dm-webhook` loops over every firing alert. Each pass runs up to two `kubectl` commands with a 15 second timeout, calls the LLM once, and posts to Slack once. Nothing caps the number of alerts.

The old 4096 byte body limit bounded this by accident, because a batch of more than a few alerts got a 413. `9691bbaa` raised the analyze limit to 262144 bytes, which is correct and is still needed.

The batch in `scripts/tests/fixtures/webhook/alertmanager-analyze-batch.json`, taken from the M5 Alertmanager on 2026-11-06, has 26 firing alerts at about 1 KB each. That is 26 LLM calls and 26 Slack posts for one delivery. At the new limit, a batch could hold about 250 alerts.

## Fix

Add `ANALYZE_MAX_ALERTS = 5` to `scripts/lib/webhook/config.py`. `_run_analyze` analyzes at most that many firing alerts, in payload order. If any are left over, it logs and sends one summary post that gives the number not analyzed and their alert names, without an LLM call. The job ends with its normal status: `success`, or `delivery_failed` if any post fails, and that includes the summary post.

## Files

- `bin/k3dm-webhook`
- `scripts/lib/webhook/config.py`
- `scripts/tests/bin/test_webhook_analyze_routing.py`

## Acceptance

```yaml
must:
  - id: M1
    text: "A batch with more firing alerts than the cap makes exactly cap LLM calls."
  - id: M2
    text: "That batch produces cap analysis posts and one summary post giving the number not analyzed and their alert names."
  - id: M3
    text: "A batch at or below the cap analyzes every firing alert and sends no summary post (paired positive control for N1)."
  - id: M4
    text: "When the summary post fails, the job ends with status delivery_failed."
must_not:
  - id: N1
    text: "The summary post does not call the LLM."
  - id: N2
    text: "Resolved alerts do not count toward the cap."
evidence:
  - {id: E1, proves: [M1, M2, M3, M4, N1, N2], kind: offline, text: "Tests using the captured 26-alert fixture, with the LLM, kubectl and Slack stubbed at their seams; M1 and M2 red on the pre-fix commit; N1 and N2 red by a mutant."}
  - {id: E2, proves: [M1, M2], kind: live, text: "After the webhook restarts on the M5, a multi-alert group gives at most cap analysis posts plus one summary; the operator confirms in #grafana-notification."}
interface:
  - "POST /api/v1/analyze"
  - "bin/k3dm-webhook _run_analyze(job_id, alert_payload, response_url)"
  - "scripts/lib/webhook/config.py ANALYZE_MAX_ALERTS"
```
