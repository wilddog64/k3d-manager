# Bug: `k3dm-cloud-request` from a host with the repo hooks times out in the pre-push fast gate

**Status:** OPEN — capture
**Priority:** P2 (proposed) — the helper cannot submit from m4 (or any checkout with `core.hooksPath=.githooks`); workaround: submit from a cloud session, which has no hooks
**Introduced by:** unknown (pre-push fast gate `abcde772`/`aa1196ed` applied to every pushed ref; the helper's data-branch push was never exempted)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** `make find-similar-docs` not run (vector store unavailable: context `k3d-k3d-cluster` missing); exact-slug pass found nothing; `docs/bugs/2026-09-28-cloud-request-helper-no-fetch-and-four-action-allowlist.md` read — different root cause
**Filed:** 2026-11-25
**Detected by:** Claude, v1.46.0 plan 1 live check (E-P1-live step a/b from m4)

## Observed

On m4 (2026-11-25 ~16:40 PST, branch `k3d-manager-v1.46.0` at `471aa526`), `bin/k3dm-cloud-request make-e2e --wait`,
`bin/k3dm-cloud-request cluster-status --wait` and `bin/k3dm-cloud-request cluster-status` each exited rc 4 after about
120 s. The only output was git's `exhaustive rename detection was skipped due to too many files` warning. `origin/cloud-requests`
stayed at `6548a5de` (2026-11-05): nothing was pushed.

## Cause

`_commit_request` (`bin/k3dm-cloud-request:60-93`) pushes a commit to `refs/heads/cloud-requests` with
`timeout=120`. `.githooks/pre-push` runs `scripts/ci/fast_gate.sh "$remote_sha"` for every pushed ref, so the base is the
old `cloud-requests` tip. That branch shares no history with the code branch (`git merge-base HEAD 6548a5de` is empty),
so `git diff --name-only "$base" HEAD` (`scripts/ci/fast_gate.sh:138`) lists the whole tree, the gate schedules a large
test set, and the helper's 120 s git timeout kills the push. The helper reports the captured output, which is only the
rename warning.

## Fix direction (for triage)

`.githooks/pre-push` skips the fast gate for `refs/heads/cloud-requests` (a data branch of request/response JSON; no code),
keeping the main-guard. Test: a pre-push run with a `cloud-requests` ref line and an unrelated `remote_sha` does not invoke
`fast_gate.sh`; a positive control with a code branch still does.
