# Bug: `k3dm-cloud-request --wait-final` waits out its timeout for actions that never get a final response

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** unknown (`--wait-final` in `bin/k3dm-cloud-request`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone)
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Severity:** low — the caller waits 300 s and gets rc 5 (timeout) although the request succeeded
**Filed:** 2026-11-26, Claude, while capturing v1.46.0 p3b proof P2 (operator go "you can go for p3b")
**Component:** `bin/k3dm-cloud-request` (wait loop, ~lines 136-180); `bin/k3dm-cloud-bridge` `_watch_entry`

## Symptom

On m4 (2026-11-26 23:06Z) `bin/k3dm-cloud-request cluster-status --wait-final` printed the initial `queued` response
(`20261126T230644Z-cluster-status`, `status: ok`) and then exited 5. The bridge writes `responses/<id>.final.json` only for
`make-*` and lifecycle actions (`_watch_entry`), so for `cluster-status` (and other non-watched queued actions) the helper
polls for a file that will never exist.

## Fix options (for triage)

1. The helper refuses `--wait-final` for actions the bridge does not watch (derive the set from the allowlist and
   `LIFECYCLE_TIMEOUTS`), with a clear message.
2. The helper treats "not watched" as final after the initial response and exits by its status.
