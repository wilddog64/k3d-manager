# Cloud bridge trusts `ledger/watching.txt` entries any pusher can write

**Status:** LANDED — `ee277703` (v1.46.0 plan 1b1), 2026-11-25; offline verified (4 new tests red on base); live check with plan 1
**Priority:** P2 (one malformed line stops every cloud request, reader requests included, until the file is fixed by hand)
**Triage:** carry → v1.46.0, fixed inside plan 1b (`docs/plans/v1.46.0-cloud-approval-b-bridge.md`), which already rewrites the watch path
**Branch:** `k3d-manager-v1.46.0`
**Introduced by:** pre-existing (watch ledger, `bin/k3dm-cloud-bridge:477-490`, `:603-624`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-25
**Prior art:** none above threshold (exact-slug glob found none; vector store unreachable)
**Detected by:** Astra (codex `gpt-6.2-astra`) blind review of v1.46.0 plan 1, 2026-11-25; confirmed by Claude against the code.

## Symptom

`cloud-requests` is a public branch any session with repo write can push. `_read_watching` (`:477-490`) accepts an entry when the keys
`request_id`, `job_id`, `created_at`, `timeout` are present; it checks no types or formats. The watch loop (`:603-624`) then runs
`float(entry["created_at"])` and `float(entry["timeout"])`: a non-numeric value raises `ValueError`, which `main` catches (`:706`), so
the tick aborts at the same point every time. The watch loop runs before the new-request scan (`:625`), so no request of any kind is
answered while the entry stays. `entry["job_id"]` is also sent to the webhook's `job-status` route without the `JOB_ID_RE` check the
request path applies.

Second layer missing: the watch loop's terminal `job-status` response is committed without the bridge's `scrub_credentials` pass that
the direct `job-status` path applies (`:646`). The webhook already scrubs job output (`scripts/lib/webhook/status.py:469`), so this is
defence in depth, not a known leak.

## Fix

Validate each entry in `_read_watching`: `request_id` matches `ID_RE`, `job_id` matches `JOB_ID_RE`, `created_at` and `timeout` are
finite numbers within sane bounds; skip (and log once) any entry that fails, so one bad line cannot stop the tick. Apply
`scrub_credentials` to `body["output"]` in the watch loop as the direct path does. Tests: a malformed line is skipped and the rest of the
tick (including a reader request) completes; a watched terminal response with a credential-shaped string in its output is scrubbed.
