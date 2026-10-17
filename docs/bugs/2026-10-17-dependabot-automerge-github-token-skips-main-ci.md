# Dependabot auto-merges never build an image: the merge push is made with GITHUB_TOKEN

**Status:** OPEN — option 1 chosen 2026-10-17; fix specified below (needs operator App setup)
**Priority:** P2 — dependency and base-image fixes merge but are not built or deployed until an unrelated
human merge; the workaround is a manual merge or a manual `workflow_dispatch`
**Severity:** Medium — silent: the PR shows MERGED and green, and nothing says the image was never built
**Found by:** Claude, 2026-10-17, branch `k3d-manager-v1.43.4`, after shopping-cart-order #90/#89/#92 merged
**Approval:** explicit 2026-10-17 "let's take option 1" (operator), on the three fix options below
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

## Fix — option 1, a GitHub App token for the merge (spec)

Auto-merge is credited to the account that enabled it. If an App installation token enables it, the
merge push is App-authored and starts `on: push` workflows, unlike a `GITHUB_TOKEN` merge.

No ruleset change is needed. The App is not a bypass actor; the merge still needs the operator's
approval and the required checks. The 2026-08-09 lesson that a user-owned App cannot be a ruleset
bypass actor does not apply here.

### Operator setup (credentials — do this before the PRs merge)

1. Create one GitHub App under your account (Settings → Developer settings → GitHub Apps → New), for
   example `k3dm-dependabot-merger`.
   - Webhook: off.
   - Repository permissions:
     - **Contents: Read and write**
     - **Pull requests: Read and write**
     - **Workflows: Read and write** — Dependabot `github-actions` bumps edit workflow files
   - Metadata: Read (set automatically).
   - "Only on this account".
2. Install it on exactly these repos: `shopping-cart-order`, `shopping-cart-payment`,
   `shopping-cart-frontend`, `shopping-cart-basket`, `shopping-cart-product-catalog`.
3. Generate a private key; note the App's **Client ID** (on the App's settings page; not a secret).
4. Set both values as **Actions and Dependabot** secrets in all five repos. Dependabot-triggered runs
   may only see Dependabot secrets, so setting both removes that question. The key is read from the
   file, never echoed:
   ```bash
   for r in order payment frontend basket product-catalog; do
     for a in actions dependabot; do
       gh secret set AUTOMERGE_APP_CLIENT_ID --app "$a" --repo "wilddog64/shopping-cart-$r" --body '<client id>'
       gh secret set AUTOMERGE_APP_PRIVATE_KEY --app "$a" --repo "wilddog64/shopping-cart-$r" < ~/Downloads/<app>.private-key.pem
     done
   done
   ```
   Then delete the downloaded `.pem`.
5. Optional cleanup: the unused `APP_ID` / `APP_PRIVATE_KEY` secrets in order, payment and basket
   (2026-08-09, referenced by no workflow) can be deleted.

### Repo change (Codex), identical in all five repos

**Branch (all work repos):** `fix/automerge-app-token`, from `origin/main`.

**F1.** `.github/workflows/dependabot-automerge.yml` — insert a token step directly before the
`Enable auto-merge for minor/patch and security updates` step:

```yaml
      - name: Mint the auto-merge App token
        # auto-merge enabled with GITHUB_TOKEN merges as github-actions, and that push never starts the image build
        id: app-token
        if: >-
          steps.meta.outputs.update-type == 'version-update:semver-minor' ||
          steps.meta.outputs.update-type == 'version-update:semver-patch' ||
          steps.meta.outputs.alert-state == 'OPEN'
        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
        with:
          client-id: ${{ secrets.AUTOMERGE_APP_CLIENT_ID }}
          private-key: ${{ secrets.AUTOMERGE_APP_PRIVATE_KEY }}
          permission-contents: write
          permission-pull-requests: write
          permission-workflows: write

```

and in the `Enable auto-merge …` step, old:
```yaml
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
new:
```yaml
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
```

Change nothing else. The `fetch-metadata` step keeps `GITHUB_TOKEN`, and frontend keeps its own
`fetch-metadata` pin. Do **not** add a fallback to `GITHUB_TOKEN`: a missing secret must fail the run
visibly, not quietly bring the bug back. The token is scoped to the current repo (the action's default
`owner`/`repositories`).

**F2.** `CHANGELOG.md` — under `## [Unreleased]` (create it above the newest version heading if it is
missing), `### Fixed`:

```markdown
- **Dependabot auto-merges now build an image.** Auto-merge was enabled with `GITHUB_TOKEN`, so the merge
  was made as `github-actions`, and GitHub starts no workflow for that push: dependency and base-image fixes
  reached `main` but no image. Auto-merge is now enabled with a GitHub App installation token
  (`AUTOMERGE_APP_CLIENT_ID` / `AUTOMERGE_APP_PRIVATE_KEY`), whose merge push runs the normal build.
```

### Files (per repo)

- `.github/workflows/dependabot-automerge.yml`
- `CHANGELOG.md`

### Rules

- `actionlint .github/workflows/dependabot-automerge.yml` is clean if `actionlint` is installed.
  Otherwise, `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/dependabot-automerge.yml`
  must succeed.
- `git diff --stat` shows only the two files.

### Definition of Done

- [ ] F1 and F2 are applied exactly in each of the five repos, with the gates' output pasted.
- [ ] The commit message is `fix(ci): enable Dependabot auto-merge with an App token so merges build`.

### What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks.
- Do NOT touch any other workflow, the ruleset, or secrets.
- Do NOT clone into a scratch directory; work in place.

### Rollout and live proof (Claude, after the operator's go)

1. Claude opens one PR per repo. The operator merges each one after its App secrets exist (setup
   step 4). Merging before that turns the next Dependabot run red, which is visible and safe.
2. Open Dependabot PRs whose auto-merge was already enabled by `github-actions` would still merge as
   `github-actions`. For each one, Claude runs `gh pr merge --disable-auto`, then re-runs its
   auto-merge workflow run, which re-enables auto-merge with the App token.
3. Proof: the next Dependabot merge shows `mergedBy` = the App (`app/<slug>`), not
   `app/github-actions`, and a `push` run of the build workflow exists for its merge commit, ending
   in a published image (`Build, Scan & Push` = success, not skipped).

## Landed on branches (2026-10-17)

Codex made the change in each repo (`codex exec`, launched from each repo). Claude checked it:

- Each diff touches only the two spec files.
- The workflow change is byte-identical in all five repos.
- `actionlint` is clean in all five.
- Each CHANGELOG entry sits under `## [Unreleased]`.

Claude then committed and pushed `fix/automerge-app-token`; origin matches local in every repo.

| Repo | Commit |
|---|---|
| shopping-cart-order | `433d0ce` |
| shopping-cart-payment | `d561af8` |
| shopping-cart-frontend | `493e862` |
| shopping-cart-basket | `de68838` |
| shopping-cart-product-catalog | `a6d60fe` |

PRs wait for the operator's App setup (secrets present in all five repos).
