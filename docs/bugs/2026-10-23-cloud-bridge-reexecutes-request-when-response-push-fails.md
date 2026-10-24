# Bug: the cloud bridge re-executes a request when its response push fails

**Status:** OPEN
**Priority:** P2
**Severity:** medium — a `make-*` request can start a second job; reads are only repeated
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude, after the operator shared a design note on duplicate request
processing (https://prachub.com/interview-questions/prevent-duplicate-request-processing)
**Approval:** explicit 2026-10-23. The operator said: "you can dispatch the bug fixing task".

**Component:** `bin/k3dm-cloud-bridge` (`process_tick`, `_write_commit`, the slow-request worker)

## Problem

`docs/howto/cloud-session-requests.md` promises at-most-once handling: "an id is consumed whether it
succeeded, was rejected, or expired". The bridge does not guarantee that.

For each new id, `process_tick` does three things, in this order:

1. Calls the webhook (`_call_webhook`).
2. Writes the response and the `ledger/processed.txt` entry (`_write_commit`). This step pushes
   with `--force-with-lease`.
3. Adds the id to the in-memory `processed` set.

If the push in step 2 fails, `_git` raises. `main` logs the error and sets `last_tip = None`.
Neither the remote ledger nor the in-memory set holds the id, so the next tick calls the webhook
again. The push can fail for two reasons:

- A lost lease: a cloud session pushed a new request while the webhook call was running. This is
  common, because a session often files a follow-up `job-status` straight away.
- A network or SSH failure, or a locked Keychain.

For a read action the cost is one extra call. For `make-test`, `make-test-pytest` or an e2e
action, it starts a second job. The e2e runner lock rejects that second job, but the first job's
id has still been answered twice. The cloud session sees whichever response landed, which may be
the `busy (lock held)` failure rather than the real job.

A crash between steps 1 and 2 has the same effect after the bridge restarts.

## Fix

The bridge is the only consumer of the branch, so a local journal can decide which ids are
claimed. It needs no extra push.

### F1. Claim before executing

Before calling the webhook for an id:

1. Append the id to `$K3DM_CLOUD_BRIDGE_STATE/claimed.txt`, flush and `fsync` it. The default
   directory is `~/.k3d-manager/cloud-bridge/`.
2. Skip any id that is already in `claimed.txt`. These are never sent to the webhook again.

This applies to every path that reaches `_call_webhook`, slow actions included.

### F2. Keep the response until it is published

After the webhook call, store the response as `$K3DM_CLOUD_BRIDGE_STATE/outbox/<id>.json` before
calling `_write_commit`. Delete the file only after the push succeeds. On each tick, before
handling any new request, retry the push for every outbox entry. Never call the webhook to rebuild
a response.

### F3. A claim with no stored response

An id that is in `claimed.txt` but has no outbox file and no remote response means the bridge
crashed mid-call. Publish `status: "error"` with the reason
`bridge restarted before the request completed; outcome unknown — file a new request`. Do not
re-execute it.

Update the how-to's "Reading the response" paragraph: name this reason, and say that a failed
push delays a response but never repeats the action.

## Tests

`scripts/tests/bin/test_cloud_bridge.py`. Use a stub webhook that counts calls, and a bare repo
whose push can be made to fail.

1. The first response push fails, then succeeds: the webhook is called once, and the response
   lands on the second tick.
2. A lease is lost because a new request was pushed during the call: the first id is called once,
   and both ids get responses.
3. An id in `claimed.txt` with no outbox file and no response gets the restart error, and the
   webhook is not called.
4. A slow action whose push fails is not queued a second time.
5. Existing tests pass unchanged.

Show tests 1–4 red against the pre-fix bridge on a temp copy.

## Files

- `bin/k3dm-cloud-bridge`
- `scripts/tests/bin/test_cloud_bridge.py`
- `docs/howto/cloud-session-requests.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Each request id reaches the webhook at most once, however many ticks, push failures or bridge restarts follow.
  - id: M2
    text: A response that failed to push is published on a later tick, from the stored copy.
  - id: M3
    text: An id claimed before a crash, with no stored response, gets status error with the restart reason.
must_not:
  - id: N1
    text: A failed response push must not cause a second webhook call for the same id.
  - id: N2
    text: The request, response and ledger formats on the cloud-requests branch must not change.
  - id: N3
    text: Tests must not push to the real origin or call the real webhook on :7443.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3]
    text: pytest scripts/tests/bin/test_cloud_bridge.py green; tests 1-4 red on the pre-fix bridge.
  - id: E2
    kind: live
    proves: [M1]
    text: Claude files a cluster-status request and, while it is in flight, a second request; the bridge log shows one webhook call per id, and both responses land.
interface:
  - bin/k3dm-cloud-bridge (process_tick; env K3DM_CLOUD_BRIDGE_REPO, K3DM_CLOUD_BRIDGE_STATE)
  - $K3DM_CLOUD_BRIDGE_STATE/claimed.txt, outbox/<id>.json
  - cloud-requests branch paths requests/, responses/, ledger/processed.txt
```

## Definition of Done

- [ ] F1–F3 and the how-to update; a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `pytest scripts/tests/bin/test_cloud_bridge.py` green; paste the summary.
- [ ] Tests 1–4 shown red on a temp copy of the pre-fix bridge.
- [ ] Commit: `fix(cloud-bridge): execute each request at most once`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT push to the real `cloud-requests` branch or call the real webhook from tests.
- Do NOT add idempotency handling to `bin/k3dm-webhook`; this fix is bridge-only.
- Do NOT modify files outside the Files list.
