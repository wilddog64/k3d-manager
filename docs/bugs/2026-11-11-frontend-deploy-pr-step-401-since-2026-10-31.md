# Bug: shopping-cart-frontend CI cannot open its deploy PR (`PACKAGES_TOKEN` 401), so no frontend image has deployed since 2026-10-27

**Status:** OPEN
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-11 (rotate `PACKAGES_TOKEN` in wilddog64/shopping-cart-frontend; merge PR #140)
**Severity:** High impact, silent. Images build, scan and push, but the live frontend stays on the last bumped tag. The CVE fix from #139 (libxslt 1.1.43-r4, CVE-2026-9947 CVSS 9.6) did not reach Hostinger. Workaround: open the deploy PR by hand from the branch CI pushed (done: #140).
**Introduced by:** unknown (the token stopped working between 2026-10-27 and 2026-10-31; secret last set 2026-10-22)
**Should have been caught by:** none (the main run fails, but nothing alerts on a failed main-branch publish run)
**Prior art:** exact-slug glob: none; grep `Bad credentials` in docs/bugs: one unrelated hit (Hermes). `make find-similar-docs` not run (vector store context missing on the M4).
**Approval:** Claude, 2026-11-11 (found while verifying #139's deploy)
**Filed:** 2026-11-11
**Detected by:** Claude, after the merge of shopping-cart-frontend #139 (run 43064482613)

## What happened

The `Build, Scan, Push & Deploy` job's last step, "Open PR to update Kubernetes manifest to the new image tag"
(`.github/workflows/ci.yml:276`, `GH_TOKEN: ${{ secrets.PACKAGES_TOKEN }}`), pushes the branch
`ci/frontend-image-sha-<sha>` and then fails on `gh pr create` with `HTTP 401: Bad credentials (https://api.github.com/graphql)`.

Same error on every main run that reached the step: 41229234374 (2026-10-31), 41572570056 and 41573127569 (2026-11-03),
42749861025 (2026-11-10), 43064482613 (2026-11-11). The last deploy PR that opened was #134 (2026-10-27).
`k8s/base/kustomization.yaml` on main is still `newTag: sha-00a96173…`.

Checked on m4-air, 2026-11-11, with `docker run … apk info -v`: deployed `sha-00a96173` has `libxslt-1.1.43-r3`;
new `sha-b04f0c1f` has `libxslt-1.1.43-r4`.

## Fix

1. Operator: rotate `PACKAGES_TOKEN` (needs `pull_requests: write` and `contents: write` on the repo), or switch this step to `GITHUB_TOKEN` with `permissions: pull-requests: write`, if the repo setting allows Actions to create PRs.
2. Make a failed main-branch publish visible: an alert or notice when the deploy step fails, so a dead token does not hide for 11 days.
3. Check the other shopping-cart repos that open deploy PRs with the same secret.
