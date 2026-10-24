# Cluster-up Slack thread recurrence investigation

**Status:** Partial — safe host job metadata found on independent follow-up; Slack-rendered placement remains unconfirmed.

**Job:** `aeeeb11f`  
**Scope:** Read-only inspection of local metadata only. No Slack API, AWS, Kubernetes, or lifecycle operation was performed.

## Findings

The worker inspected its task-scoped `K3DM_JOB_DIR`, `K3DM_LOG_DIR`, and `K3DM_STATE_DIR`; those directories were empty. That did not inspect the host job store and was insufficient to conclude that local evidence was unavailable. A separate read-only follow-up inspected only safe fields in the host job directory and projected safe delivery fields. It did not open `response_url`, `output`, or `failure.md`.

The safe job fields were `action=up`, `status=failed`, `thread_ts=1792615012.460159`. The delivery log contains five successful response_url deliveries without a thread timestamp, a successful bot fallback without a thread timestamp, and three later response_url attempts using that parent timestamp rejected with `thread_post_rejected`; `channel_id` was null in all records. This supports a thread-context/routing problem, but records do not contain returned message timestamps or per-notification event labels. It does not identify which entry corresponds to failure analysis or prove Slack's rendered placement.

## Evidence

```text
$ find "$K3DM_JOB_DIR" -maxdepth 3 -iname '*aeeeb11f*' -print
[no output]

$ find "$K3DM_JOB_DIR" -maxdepth 2 -type f -print | wc -l
0
$ find "$K3DM_LOG_DIR" -maxdepth 2 -type f -print | wc -l
0
$ find "$K3DM_STATE_DIR" -maxdepth 3 -type f -print | wc -l
0
```

## Conclusion

Local records show failed threaded-delivery/fallback behavior, but do not link a specific entry to the failure-analysis message, and no Slack API/UI metadata was checked. Treat this as corroborating routing evidence, not proof of rendered placement or a verified fix. Keep the bug open. No code fix is proposed by this investigation.
