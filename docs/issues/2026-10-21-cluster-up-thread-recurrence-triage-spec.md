# Dispatch spec: cluster-up Slack thread recurrence triage

Read-only triage of job `aeeeb11f` to determine whether its failure-analysis message lost the originating Slack thread, and identify the delivery path from persisted local metadata. Investigation only: do not edit code or claim a fix.

Use only safe local fields `action`, `status`, `thread_ts`, `channel_id`, and `thread_source`; inspect only sanitized delivery record fields needed to correlate route and returned timestamps. Never read or print `response_url`, `output`, or `failure.md`; do not call Slack APIs or run AWS, Kubernetes, or lifecycle operations. If evidence is unavailable, say so.

Write findings only to `docs/issues/2026-10-21-cluster-up-thread-recurrence-investigation.md`.

## Files

- `docs/issues/2026-10-21-cluster-up-thread-recurrence-investigation.md`
