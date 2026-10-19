# Bug: PR Checks dashboard never shows shopping-cart pull requests

**Filed:** 2026-10-18 (Claude, from an operator screenshot)
**Status:** OPEN
**Priority:** P3 — observability gap; the PRs and their checks are still visible on GitHub
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "go ahead to do that" (filing; dispatch not yet approved)
**Release:** v1.43.7 (bug; exempt from the plan cap)
**Component:** `scripts/lib/hermes/pr_checks.py` (`REPOS`), `docs/guides/grafana-dashboards.md`
**Related:** `docs/plans/v1.43.3-pr-checks-dashboard.md` (introduced the dashboard);
`docs/plans/v1.43.7-codex-dispatch-cross-repo.md` (the same cross-repo research data, for dispatches)

## Symptom

On 2026-10-18 shopping-cart-frontend PR #127 had red `lint` and `type-check` runs, two fix commits and
a green rerun, and PR #128 then promoted its image. None of it appeared on **k3dm PR Checks**: over
24 hours the dashboard showed only k3d-manager #145. The operator wants cross-repo PR and CI data for
research.

## Root cause

The collector polls a fixed list:

```python
REPOS = ("wilddog64/k3d-manager", "wilddog64/lib-foundation")
```

`_publish_pr_checks` in `bin/k3dm-hermes` loops over `pr_checks.REPOS` and pushes one Pushgateway group
per repo (`instance=<repo name>`). A repo that is not in the list is never read.

## Fix

- **F1.** Extend `REPOS` in `scripts/lib/hermes/pr_checks.py`. Keep the two existing entries first,
  then add, in this order:
  `wilddog64/shopping-cart-basket`, `wilddog64/shopping-cart-e2e-tests`,
  `wilddog64/shopping-cart-frontend`, `wilddog64/shopping-cart-infra`,
  `wilddog64/shopping-cart-order`, `wilddog64/shopping-cart-payment`,
  `wilddog64/shopping-cart-product-catalog`.
  Change nothing else in the module or in `bin/k3dm-hermes`.
- **F2.** Tests in `scripts/tests/hermes/test_pr_checks.py` and `scripts/tests/hermes/test_hermes.py`.
  Update the existing assertion that the pushed instances are exactly `["k3d-manager", "lib-foundation"]`
  to the new nine-repo list.
- **F3.** In the **k3dm PR Checks** section of `docs/guides/grafana-dashboards.md`, replace "for
  k3d-manager and lib-foundation" with the repo list, and add:
  - **GitHub read** is the minimum across the selected repos. Use the Repo filter to find which one
    failed.
  - A repo whose reads have always failed is missing from the Repo filter, because the filter is built
    from `k3dm_pr_checks_open_prs`.
  - The Hermes GitHub token needs read access to every listed repo.

The dashboard needs no change: the Repo variable is `label_values(k3dm_pr_checks_open_prs, repo)` and
every panel already filters by `repo`.

**Live risk:** the Hermes GitHub token is a fine-grained PAT. If its repository selection does not
include a shopping-cart repo, that repo pushes `scrape_success 0` and **GitHub read** turns red. If
that happens, the operator widens the PAT's repository selection; Claude does not handle the token.

## Acceptance

```yaml
must:
  - id: M1
    text: pr_checks.REPOS is k3d-manager, lib-foundation, then the seven shopping-cart repos listed in F1, in that order.
  - id: M2
    text: One Hermes PR-checks publish pushes one group per repo, at /metrics/job/k3dm-pr-checks/instance/<repo name>, and an open PR in a shopping-cart repo appears as k3dm_pr_info{repo="wilddog64/<name>"} with its check series.
  - id: M3
    text: The guide section lists the repos and has the three notes in F3.
must_not:
  - id: N1
    text: An open shopping-cart-frontend PR must not be missing from the pushed metrics (red on pre-fix, which never reads that repo).
  - id: N2
    text: A failed GitHub read for one repo must not stop or change the PUT for any other repo; k3d-manager and lib-foundation must still be pushed, with no metric name or label changed.
  - id: N3
    text: Tests must not call api.github.com or push to the live hub Pushgateway.
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    text: pytest scripts/tests/hermes with a fake fetch and a fake urlopen; a frontend PR fixture appears in the frontend group's body; one repo's fetch raises and the other eight are still PUT; N1 red on the pre-fix REPOS.
  - id: E2
    proves: [M3]
    kind: offline
    text: grep the guide section for each repo name and the three notes.
  - id: E3
    proves: [M2]
    kind: live
    text: Claude, after the hub Hermes runs the fix, reads the PR Checks dashboard (operator screenshot); the Repo filter lists the shopping-cart repos and GitHub read is ok, or the failing repo is named and the operator widens the token.
interface:
  - scripts/lib/hermes/pr_checks.py REPOS, collect(fetch, repo), render(prs, now, repo)
  - bin/k3dm-hermes _publish_pr_checks(now), K3DM_PR_CHECKS_PUSHGATEWAY_URL
  - Pushgateway job k3dm-pr-checks, metrics k3dm_pr_info, k3dm_pr_check_state, k3dm_pr_checks_open_prs, k3dm_pr_checks_scrape_success
```

## Definition of Done

- [ ] F1–F3 on `k3d-manager-v1.43.7`; only the three listed files plus `CHANGELOG.md` change.
- [ ] N1 shown red against the pre-fix `REPOS`.
- [ ] `pytest scripts/tests/hermes` green.
- [ ] Commit: `fix(hermes): PR checks cover the shopping-cart repos`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT read, print or change the Hermes GitHub token.
- Do NOT change the dashboard JSON, metric names or labels.
- Do NOT dispatch with a bare `codex exec`; use `bin/k3dm-codex-dispatch`.

## Verification log

- 2026-10-18: filed. GitHub shows k3d-manager #145 open 05:56–12:01 PDT, matching the dashboard; the
  shopping-cart-frontend #127/#128 activity the same day is absent.
- 2026-10-18: live risk cleared. Operator screenshot: `k3dm-hermes-gh-token` already covers all seven shopping-cart repos plus k3d-manager and lib-foundation, with Actions, Checks, Commit statuses and Contents read-only. It has no Pull requests permission, but all nine repos are public, the same way k3d-manager PR listing already works.
