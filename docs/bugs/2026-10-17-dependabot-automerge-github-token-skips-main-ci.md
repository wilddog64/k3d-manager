# Dependabot auto-merges never build an image: the merge push is made with GITHUB_TOKEN

**Status:** OPEN — needs the operator's decision on the merge credential (below)
**Priority:** P2 — dependency and base-image fixes merge but are not built or deployed until an unrelated
human merge; the workaround is a manual merge or a manual `workflow_dispatch`
**Severity:** Medium — silent: the PR shows MERGED and green, and nothing says the image was never built
**Found by:** Claude, 2026-10-17, branch `k3d-manager-v1.43.4`, after shopping-cart-order #90/#89/#92 merged
**Approval:** filed on Claude's own call (bug filing); the fix needs the operator's go — it needs a credential
**Related:** `docs/plans/v1.27.0-dependabot-automation.md` (the design that introduced this),
`docs/bugs/2026-10-06-shopping-cart-order-go-dependabot-coverage-gap.md`,
`docs/bugs/2026-10-17-services-digest-pin-not-bumped-by-app-ci.md`

## Symptom

shopping-cart-order #90 (`alpine:3.24`), #89 and #92 (`golang:1.27-alpine`) merged at 12:49–12:57 UTC on
2026-10-17, all `mergedBy=app/github-actions`. No `push` run of `ci.yml` (Build, Scan & Push) or Go CI exists
for their merge commits (`4bf85a1`, `0718b77`, `0d59e22`). The only workflow on `main` afterwards was
"Dependabot Updates". The `musl` CVE fix from #90 is in `main` and in no image.

## Cause

`.github/workflows/dependabot-automerge.yml` runs `gh pr merge --auto --squash` with
`GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`. When auto-merge fires, the merge is made as `github-actions`, and
GitHub does not start workflows for events caused by `GITHUB_TOKEN` (other than `workflow_dispatch` and
`repository_dispatch`). So the `on: push: branches: [main]` build never runs. The v1.27.0 plan does not mention
this.

## Scope

| Repo | automerge workflow | merged by `github-actions` (last 30 merged PRs) |
|---|---|---|
| shopping-cart-order | yes | 8 |
| shopping-cart-payment | yes | 7 |
| shopping-cart-frontend | yes | 16 |
| shopping-cart-basket | yes | 14 |
| shopping-cart-product-catalog | yes | 0 |
| shopping-cart-e2e-tests, shopping-cart-infra | no | 0 |

Each bot merge's change shipped only when a later human-merged push triggered a build, which bundles it in.

## Fix options (operator decision)

1. **GitHub App token for the merge (recommended).** Mint a token with `actions/create-github-app-token` and
   use it as `GH_TOKEN` for `gh pr merge --auto`. App-authored pushes do trigger workflows. Needs an App
   installed on the shopping-cart repos, and its id + private key as repo/org secrets (operator-only). This also
   matches `reference_github_actions_bot_no_ruleset_bypass_personal_repo`.
2. **Dispatch the build after merge.** Add `workflow_dispatch` to the build workflow, plus a job that runs
   `gh workflow run` with `GITHUB_TOKEN` on `pull_request_target: closed` + merged. No new credential, but the
   build is then decoupled from the `push` event, and every repo's build workflow changes.
3. **Stop auto-merging.** Leave Dependabot PRs for a human merge. Simplest; loses the automation.

## Immediate workaround

shopping-cart-order PR #99 is human-merged, so its push will build an image containing #90, #89 and #92 too.
