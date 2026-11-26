# Bug: `k3dm-cloud-request` from a host with the repo hooks times out in the pre-push fast gate

**Status:** OPEN — capture
**Priority:** P2 (proposed) — the helper cannot submit from m4 (or any checkout with `core.hooksPath=.githooks`); workaround: submit from a cloud session, which has no hooks
**Introduced by:** unknown (pre-push fast gate `abcde772`/`aa1196ed` applied to every pushed ref; the helper's data-branch push was never exempted)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-25
**Triage:** fix now in v1.46.0 (operator, 2026-11-25: "can we do 1, and 2")
**Branch:** `k3d-manager-v1.46.0`
**Implementer:** Gemini 4 Neon (`--agent agy --model gemini-4-neon-high`), model trial (operator, 2026-11-25)
**Intent approved:** operator, 2026-11-25
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

## Fix

In `.githooks/pre-push`, a ref line whose `remote_ref` is `refs/heads/cloud-requests` adds nothing to `bases` and, when
it is the only ref pushed, the fast gate is not run (print `pre-push: fast gate skipped for refs/heads/cloud-requests (data
branch)`). Any other ref in the same push still contributes its `remote_sha` and runs the gate as today. The main-guard
loop is unchanged. A push of only `cloud-requests` whose remote ref is new (all-zero `remote_sha`) must also skip the gate
(today the empty `bases` path runs `fast_gate.sh` with no base).

## Files

- `.githooks/pre-push`
- `scripts/tests/lib/fast_gate.bats`

## Scope

- Change: `.githooks/pre-push`.
- Tests: `scripts/tests/lib/fast_gate.bats` (new tests next to "pre-push rejects lint failure and preserves main guard",
  reusing its fixture: bare remote, `core.hooksPath .githooks`, a broken `one.bats` as the red control).
- Out of scope: `scripts/ci/fast_gate.sh`, `bin/k3dm-cloud-request` (its timeout message is a separate P3), `bin/k3dm-cloud-bridge`.

## Contract readers

`.githooks/pre-push` is read by git on every push from a checkout with `core.hooksPath=.githooks`:
`bin/k3dm-cloud-request:86-89` (writer of `refs/heads/cloud-requests` from operator hosts; changes: its push no longer
runs the gate), `bin/k3dm-cloud-bridge` response pushes on the hub (unchanged behaviour when the hub checkout has no hooks
path; with hooks, they also stop running the gate), `bin/k3dm-codex-dispatch:1518` (`K3DM_SKIP_FAST_GATE`, unchanged),
`scripts/tests/lib/fast_gate.bats:179-201` (existing guard test, must stay green).

## Acceptance

```yaml
must:
  - id: N-M1
    text: A push of only refs/heads/cloud-requests, with an unrelated existing remote tip, exits 0 without running fast_gate.sh and prints the data-branch skip line.
  - id: N-M2
    text: A push of only refs/heads/cloud-requests to a remote where it does not exist yet exits 0 without running fast_gate.sh.
  - id: N-M3
    text: A push of a code branch together with refs/heads/cloud-requests still runs the fast gate with the code branch's remote tip as base, and fails on the broken one.bats.
must_not:
  - id: N-N1
    text: Pushing refs/heads/cloud-requests must not run fast_gate.sh (red on pre-fix code - the gate runs and fails on the broken one.bats).
  - id: N-N2
    text: The main guard must not be weakened - pushing a non-main ref to refs/heads/main is still refused, alone or alongside cloud-requests.
evidence:
  - id: E-N1
    proves: [N-M1, N-N1]
    kind: offline
    intent: "When the cloud request helper submits a request from your Mac, git's push check no longer runs the full test gate on that data-only branch, so the request reaches the hub within seconds instead of timing out."
    command: bats scripts/tests/lib/fast_gate.bats
  - id: E-N2
    proves: [N-M2]
    kind: offline
    intent: "The very first request pushed to a fresh cloud-requests branch is also exempt, so setting up a new remote cannot hit the same timeout."
    command: bats scripts/tests/lib/fast_gate.bats
  - id: E-N3
    proves: [N-M3, N-N2]
    kind: offline
    intent: "Code pushes keep their full protection: a broken test still blocks a branch push even when a cloud request rides along in the same push, and nothing can be pushed straight to main."
    command: bats scripts/tests/lib/fast_gate.bats
  - id: E-N4
    proves: [N-M1]
    kind: live
    intent: "From m4, bin/k3dm-cloud-request cluster-status --wait gets its answer from the hub, showing the helper works again from your own Mac."
    command: bin/k3dm-cloud-request cluster-status --wait (Claude, m4, after land)
interface:
  files: [.githooks/pre-push, scripts/tests/lib/fast_gate.bats]
  red_on_base: [N-N1]
```
