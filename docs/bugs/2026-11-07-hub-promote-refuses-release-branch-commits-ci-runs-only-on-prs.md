# Bug: `make hub-promote` refuses every release-branch commit, because CI runs only on pull requests

**Status:** LIVE-VERIFIED 2026-11-11 — Claude read the operator's latest promote tag `hub-promote/20261110T234204Z` (`74cd3ca1` → `cf86a93f`, a release-branch commit): no `mode: break-glass` line, so the check-run gate passed on its own. Was: VERIFIED — 2026-11-08: push CI run 42481822700 green on `86585e4c`; the operator's `make hub-promote` on M5 passed the check-run gate without BREAK_GLASS (tag `hub-promote/20261108T131509Z`)
**Fix commit:** `efb035fe`
**Live evidence:** 2026-11-11 · run hub-promote-20261110T234204Z · env m5-air · scenario release-branch-promote-without-break-glass · commit cf86a93f · proves fix
**Priority:** P2
**Introduced by:** `897cfe72` (v1.43.15, hub-deploy-ref)
**Should have been caught by:** spec
**Severity:** medium — the hub cannot be promoted to a release-branch commit, so no live check of ArgoCD or platform-ops changes can run during development without `BREAK_GLASS=1`
**Approval:** filed by Claude during the v1.43.15 WIP drain; fix choice is the operator's
**Filed:** 2026-11-07
**Detected by:** Claude, while writing the `deploy/hub` bootstrap lines for the operator
**Affected:** `bin/k3dm-hub-promote` (`check_runs`, `:42`), `.github/workflows/ci.yml` (`on:`), `docs/howto/hub-promote.md`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

`check_runs` dies with `no GitHub check runs exist for <sha>` when the commit has no check runs. Commits pushed
to a release branch have none:

- `gh api repos/wilddog64/k3d-manager/commits/8153f9eb/check-runs --jq .total_count` → `0` (2026-11-07, Claude's M4 session)
- same for `79c722ce` → `0`
- `.github/workflows/ci.yml` triggers only on `pull_request` (`types: [opened, synchronize, reopened]`); `deploy-worker.yml` is not a CI gate.

So `make hub-promote REF=k3d-manager-v1.43.15` refuses until the release PR is open. The release PR waits on live
checks (CLAUDE.md PR creation gate), and live checks wait on a promote: a deadlock. The only way through today is
`BREAK_GLASS=1`, which `docs/howto/hub-promote.md` reserves for outages.

The bootstrap in `docs/howto/hub-promote.md` hits the same wall: `deploy/hub` does not exist on `origin`, and
`make platform-ops` fails closed until the first promote.

## Root cause

The plan (`docs/plans/v1.43.15-hub-deploy-ref-and-live-write-guard.md`, step 2) assumed release-branch commits
carry check runs. That is external behaviour (this repo's Actions triggers) and was not proven before dispatch.
The offline tests stub `gh api …/check-runs` with runs present, so they share the assumption.

## Fix options (operator decision)

1. **Run CI on pushes to release branches** — add `push: branches: ['k3d-manager-v*']` to `ci.yml`. Every
   release-branch commit gets check runs; the gate works as written. Cost: more Actions runs (a PR push runs both
   events unless `concurrency` dedupes them).
2. **Open the release PR early** — check runs then exist for the PR head. Conflicts with the no-draft-PR practice
   and the PR creation gate.
3. **Allow promoting an unchecked commit for live checks** — e.g. a `DEV=1` mode that skips check runs but records
   it in the tag. Weakens the gate the plan added.

Claude recommends option 1.

## Live check — 2026-11-08 (operator on M5; refs checked by Claude from M4)

- CI on push: runs 42478234554 (`f454ad13`, red), 42479985975 (`84268ee6`, red), 42481822700 (`86585e4c`,
  green), all triggered by pushes to `k3d-manager-v1.43.15`. The check-run gate now has runs to read.
- `make hub-promote REF=86585e4c6a860bc35834365e20d56663a8c1c647` (no BREAK_GLASS): created `deploy/hub` at
  `86585e4c`; tag `hub-promote/20261108T131509Z` (`fcb486f0`) peels to `86585e4c` (`git ls-remote origin`).
  The first try failed in the pre-push fast gate: PyYAML missing on M5 (`ci_workflow_no_stage2.bats`). The
  retry ran with `K3DM_SKIP_FAST_GATE=1`; that test is green in run 42481822700 on the same commit.
- `make hub-promote-status`: `deploy/hub: 86585e4c…`, `k3d-manager-v1.43.15 ahead of deploy/hub: 0`.
- `make appsets-check`: "checked 21 k3d-manager references (2 tracking HEAD, ignored)", "All Applications
  reference values branch deploy/hub".
- `make platform-ops`: "[platform-ops] applied deploy/hub 86585e4c…"; four Keychain items unreadable (login
  Keychain locked), so those secrets were left as they were.
- `kubectl -n platform-ops rollout status deploy/vulnerability-inventory-exporter`: "successfully rolled out".

