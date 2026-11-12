# Bug: hub-promote tags a promote that moves nothing, and a later rollback goes nowhere; push failures all read "lease rejected"

**Status:** LANDED — `98942bdb` on `k3d-manager-v1.43.15` (2026-11-08); Claude review: added streaming of the push output through `tee` (Luna's version captured it, hiding the minutes-long pre-push gate); 25/25 `hub_promote.bats` outside the sandbox
**Priority:** P2
**Waiting on:** live check — since 2026-11-08 (offline verifier passed; E2 'already at' promote on M5)
**Introduced by:** `897cfe72` (v1.43.15, deploy/hub ref with make hub-promote, hub-rollback and hub-promote-status)
**Should have been caught by:** spec
**Severity:** medium — `make hub-rollback`, the recovery lever, currently returns `deploy/hub` to the commit it is already on; the operator must roll back twice and may not notice. Workaround: run it twice.
**Approval:** operator, 2026-11-08 ("go ahead to file those and dispatch to Luna/Flash 3.8 base on our rules")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** Claude, `git ls-remote origin 'refs/tags/hub-promote/*'` after the second promote
**Affected:** `bin/k3dm-hub-promote` (`main` promote path, `record_move`, `resolve_on_origin`, `rollback`)
**Branch:** `k3d-manager-v1.43.15`

## Symptom

1. The operator ran `make hub-promote REF=61195319…` twice on M5, 1 min 42 s apart. `deploy/hub` was already at
   `61195319` the second time, yet the tool asked for confirmation, pushed, and recorded a second tag. Origin now has
   `hub-promote/20261108T134641Z` and `hub-promote/20261108T134823Z`, both peeling to `61195319`.
2. `rollback` replays the tags into a stack: `[86585e4c, 61195319, 61195319]`. Its target is the second-to-last entry,
   `61195319`, which is the current `deploy/hub`. A rollback now moves nothing.
3. On the first bootstrap try, the push failed because the pre-push fast gate failed (PyYAML missing on M5). The tool
   printed `deploy/hub changed after it was read; lease rejected the push` (`bin/k3dm-hub-promote:82`) for a push that
   no lease had rejected. Every push failure gets this message.
4. `REF` is resolved with `git rev-parse` (`resolve_on_origin`). A branch name finds the local branch before
   `origin/<branch>`. When they differ, the tool promotes the local branch's commit, which can be older than the
   origin commit the operator meant, without saying so. Today we passed a SHA to avoid it.

## Fix

- Promote: when the resolved commit equals the current `deploy/hub`, print `deploy/hub is already at <sha>; nothing
  to promote` and exit 0, before the check-run lookup, the confirmation, the push and the tag.
- Rollback: consecutive promotions of the same commit count once when the stack is built, so the target is the
  previous **distinct** commit. Do not delete or rewrite existing tags.
- Push failure: report git's real reason. Print the lease message only when git reports a lease failure (`stale
  info`); otherwise `push to deploy/hub failed; see git's output above (a pre-push hook, the network or permissions)`.
- REF: when REF names a branch that exists both locally and as `origin/<REF>` at different commits, stop and name both
  SHAs. A full SHA, a tag, or a branch whose local and origin copies match resolve as today.

## Files

- `bin/k3dm-hub-promote`
- `scripts/tests/bin/hub_promote.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "promote with REF resolving to the commit deploy/hub already points at exits 0, prints 'already at', and pushes nothing and creates no tag"
  - id: M2
    text: "rollback with promotion tags A, B, B (same commit promoted twice) moves deploy/hub to A"
  - id: M3
    text: "a push that fails for a reason other than a lease (for example a pre-push hook exiting 1) exits non-zero without the words 'lease rejected'"
  - id: M4
    text: "REF naming a branch whose local copy differs from origin/<branch> exits non-zero and prints both SHAs, before any push"
must_not:
  - id: N1
    text: "a real promote of a new commit stops pushing or tagging (paired positive control for M1: deploy/hub moves and exactly one tag is recorded)"
  - id: N2
    text: "rollback with tags A, B, C moves anywhere but B (paired control for M2: distinct promotions keep today's behaviour)"
  - id: N3
    text: "a genuine lease failure stops being reported as a lease rejection"
  - id: N4
    text: "existing hub-promote tags are deleted or rewritten"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    intent: "tests run hub-promote against a scratch git remote (never origin) and check what it pushes, tags and prints in each case"
  - id: E2
    proves: [M1]
    kind: live
    intent: "the operator reruns make hub-promote with the current deploy/hub SHA on M5 and sees 'already at', with no new tag on origin"
  - id: E3
    proves: [M2]
    kind: offline
    intent: "Claude replays today's real tag list (86585e4c, 61195319, 61195319) through rollback against a scratch remote and it targets 86585e4c; no live rollback is run"
interface:
  - "bin/k3dm-hub-promote promote REF | rollback | status (make hub-promote, hub-rollback, hub-promote-status)"
  - "REPO_ROOT resolved from the script's own location; tests point it at a scratch clone whose origin is a scratch bare repo"
  - "gh check-run lookup: BREAK_GLASS=1 skips it, or stub gh on PATH"
```

## Notes

- Test fixtures must assert first that the clone's `origin` is the scratch bare repo, not GitHub (CLAUDE.md test
  controls: verify the target before the result).
- The two duplicate tags on origin stay as they are (N4); M2 makes rollback read them correctly.

## Independent verification — 2026-11-08

Gemini 3.8 Flash (`gemini-3.8-flash-medium`) wrote 9 tests from the Acceptance block only (fix spec removed from its
clone): against `98942bdb` 9/9 pass (rc 0); against pre-fix `4cf0b01c` rc 1, red on M1, M2, M3, M4 and E3, green on
N1–N4 as expected. Claude reran the suite against `98942bdb`: 9/9. Recorded with `k3dm-codex-dispatch verify` (pass).
