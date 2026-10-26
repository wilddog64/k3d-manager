# VectorDB retrieval dashboard stays empty during probe

**Status:** OPEN — **Priority:** P2
**Date:** 2026-10-26
**Release:** v1.43.9
**Approval:** pending
**Observed on:** m4-air, Hermes LaunchAgent
**Related:** `docs/plans/v1.43.9-vectordb-retrieval-quality-probe.md`

## What was checked

The Grafana Retrieval quality row was deployed, but all four panels displayed “No data”.
The exporter and rule names are present in the landed branch. On m4-air, Hermes state and
process inspection showed the scheduled run had not persisted a probe attempt and was still
running under the Hermes LaunchAgent.

Verbatim state selection:

```text
{
  "retrieval_probe_last_attempt": null,
  "index_last_success": 1793055492.1378849,
  "index_ref": "origin/k3d-manager-v1.43.9"
}
```

The saved index-success epoch is 2026-10-26 15:58:12 PDT. Hermes logs contain repeated
GitHub fetch failures:

```text
vectordb index refresh skipped: git fetch failed: ssh: connect to host github.com port 22: Undefined error: 0
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
```

An interactive `git fetch origin k3d-manager-v1.43.9` from m4-air later succeeded, but the
existing Hermes process had already started its tick. At 16:25 PDT the process was still running;
its child was:

```text
63350 32857 00:01 security find-generic-password -s gemini-cli-api-key -w
```

A retrieval evaluation runs 53 labelled searches. Each search reaches `prior_art.embed_batch()`,
which calls `api_key()`; that function retries both Keychain items before its Vault fallback.
The current implementation does not reuse the credential within the probe, so Keychain access
can delay every query in a launchd run. Probe metrics are pushed only after all evaluation and
currentness checks finish.

## Root cause

The dashboard is empty because Hermes has not completed and persisted a successful probe.
The current tick first encountered GitHub SSH fetch errors; the retry after network recovery
then spent a long time resolving the embeddings credential through Keychain. The local state
still showed `retrieval_probe_last_attempt: null`, and no retrieval-probe completion log had
been written when checked.

## Recommended follow-up

1. Resolve the embeddings credential once per evaluation and reuse it for each search, without
   logging or exporting it to child processes.
2. Ensure Hermes reports a concise completion or failure line for the probe.
3. After the fix is approved and deployed, verify that the attempt timestamp advances, the
   `k3dm-vectordb-retrieval` Pushgateway job appears, and Grafana shows the four metrics.
4. Recheck GitHub SSH reachability from the LaunchAgent context.

No process was killed or restarted and no live pytest, embedding request, or deployment was
started as part of this diagnosis.
