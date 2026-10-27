# Exit 127 attempts have local logs but an empty Grafana log view

## Attempt and actual evidence

Operator clicked Log on `vectordb-retrieval-key-cache` and
`vectordb-retrieval-key-cache-retry`, both outcome failed / exit127.
Grafana had no content. Direct reads of their retained local codex.log files:

```text
env: codex: No such file or directory
env: node: No such file or directory
```

The original local codex.log is 38 bytes, not empty. These historical starts
were abandoned; `vectordb-retrieval-key-cache-retry2` succeeded and landed
`8237c54d92af251584b29821d00d0af0a660f434`. The failed rows correctly retain
their failure outcome; successful retry does not rewrite them.

## Cause

`bin/k3dm-dispatch-metrics` `_evidence_details()` exposes the local codex.log
path for codex_exit.exit. The Log field links into the Loki run-log dashboard.
`bin/k3dm-dispatch-logs` ships only land-test.log / land_refused.tests evidence,
and that dashboard explicitly says codex.log is never shipped. These starts
never reached landing tests, so the linked view has no shipped log. This is
a source-level explanation; no live Loki API query was performed.

## Follow-up

Preserve the explicit no-codex.log-shipping decision in the original
2026-10-25 dispatch-run-log bug. Display an accurate unavailable/local-only
explanation or avoid offering an empty Loki link for unsupported evidence.
If a startup diagnostic export is desired, separately scope bounded sanitized
startup categories; never ship arbitrary worker transcripts. No log-shipping
code or historic ledger records changed in this investigation.

[Operator failed-attempt rows and Log links](../assets/2026-10-27-dispatch-startup-empty-log.png).
