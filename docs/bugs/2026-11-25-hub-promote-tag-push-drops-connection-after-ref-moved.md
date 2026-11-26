# Bug: hub-promote's tag push runs the fast gate and loses the SSH connection after deploy/hub already moved

**Status:** OPEN — capture
**Priority:** P2 — the promote stops half-done: `appsets-check`/`platform-ops` skipped and no audit tag, so `hub-rollback` loses this promotion; workaround is a re-run plus a hand-made tag
**Introduced by:** unknown (the pre-push fast gate and the tag push both predate this; the 2026-11-25 `v1460-prepush` fix exempted only `cloud-requests`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-25
**Classified:** P2 — Argon (`gemini-4-argon-medium`, blind), 2026-11-25: deploy stops after moving `deploy/hub`; re-run completes it, tag can be pushed by hand.
**Prior art:** `docs/bugs/2026-11-08-hub-promote-no-op-promote-tags-and-breaks-rollback.md` (exact-slug glob; read, different root cause: no-op promotes tagging, push output hidden); `make find-similar-docs` unavailable (vector store context missing)
**Filed:** 2026-11-25
**Detected by:** operator, 2026-11-25 ~21:05 PST, `make hub-deploy REF=5d6807880d98916de5810a681c8f2642e3790efb` on m5

## Observed

```
   cf653419e..5d6807880  5d6807880d98916de5810a681c8f2642e3790efb -> deploy/hub
fast-gate: 73 more tests name touched files — run make test
Connection to github.com closed by remote host.
```

Read-only `make hub-promote-status` afterwards (Claude, m4): `deploy/hub` = `5d680788`, newest tag still
`hub-promote/20261126T002621Z` (the previous promote). No tag for this promote.

## Cause (from the code)

- `bin/k3dm-hub-promote:183-193`: push `deploy/hub` (lease), then create and push the annotated tag; a failed tag push
  dies with "deploy/hub moved, but tag push failed".
- `.githooks/pre-push:9-36`: only `refs/heads/cloud-requests` skips the fast gate. Both pushes run it; the tag push has
  an all-zero remote SHA, so no base is collected and `scripts/ci/fast_gate.sh` runs with no base (line 36). The SSH
  connection to GitHub sits idle while the gate runs and is closed by the remote.
- `bin/k3dm-hub-deploy:146`: a non-zero promote stops the run, so `appsets-check` and `platform-ops` (line 204) never run.

## Workaround

Re-run `make hub-deploy REF=<same sha>`: promote prints "deploy/hub is already at …; nothing to promote" and exits 0
(`bin/k3dm-hub-promote:409-411`), then the remaining steps run. The missing tag stays missing (rollback history gap)
unless created by hand with the same message format.

## Fix direction (for triage)

Skip the fast gate in pre-push for `refs/heads/deploy/hub` and `refs/tags/hub-promote/*` (the commit was already gated
when it reached the release branch, and hub-promote requires green CI on it), or push the branch and tag in one
`git push` so the hook runs once; make a failed tag push retryable without re-moving the ref.
