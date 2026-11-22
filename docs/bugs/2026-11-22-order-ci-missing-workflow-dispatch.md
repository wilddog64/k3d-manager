# Bug: order CI cannot accept the scanner's rebuild dispatch

**Status:** OPEN — captured 2026-11-22; triaged 2026-11-22 (operator: fix now, spec + Luna)
**Priority:** P2
**Introduced by:** pre-existing (order's `ci.yml` has never had a `workflow_dispatch` trigger)
**Should have been caught by:** spec — the 2026-10-27 product-catalog fix covered one repository and did not check the other app repositories
**Introducing change reviewed:** unknown
**Classified:** P2 by gemini-4-argon-medium, 2026-11-22 (Automated CVE rebuild dispatches for `shopping-cart-order` always fail and wipe its build cache because `.github/workflows/ci.yml` lacks `workflow_dispatch`, requiring a manual push to `main`.)
**Waiting on:** operator decision — since 2026-11-22 (merge order PR #109)
**Triage:** patch → fix now in `wilddog64/shopping-cart-order` (operator 2026-11-22: "Fix now"; route "Spec + Luna"). The optional k3d-manager scanner part (Fix direction 2) carries to v1.46.0 as P3.
**Spec reviewed:** Fable 2026-11-22 (needs changes: 5 should-fix, 2 nits, all applied)
**Intent approved:** operator, 2026-11-22
**Intent note:** E1-E3 as shown to the operator after the Fable review; dispatch Luna approved the same day.
**Prior art:** `docs/bugs/2026-10-27-product-catalog-ci-missing-workflow-dispatch.md` (exact-slug grep, not scored) — read, same root cause in another repository; new doc because the fix lands in `wilddog64/shopping-cart-order`
**Filed:** 2026-11-22
**Detected by:** Claude, reading the manual `app-cve-scan-manual` job log on the m5 hub after the scanner PAT was replaced
**Repository:** wilddog64/shopping-cart-order
**Affected file:** `.github/workflows/ci.yml` on main (scanner mapping: `_build_workflow_for_service` in `scripts/etc/argocd/platform-ops/app-cve-scan.sh`)

## Symptom

Hub job `platform-ops/app-cve-scan-manual`, 2026-11-22 18:45 UTC:

```text
[app-cve-scan] STAGE shopping-cart-order: 4 HIGH/CRITICAL CVE(s) on deployed image ghcr.io/wilddog64/shopping-cart-order@sha256:61e19711...
[app-cve-scan] STAGE shopping-cart-order: cleared 24 build cache entries
[app-cve-scan] STAGE shopping-cart-order: rebuild dispatch FAILED — will retry next run
```

The same run dispatched basket (`go-ci.yml`), frontend (`ci.yml`), payment (`ci.yaml`) and product-catalog (`ci.yml`);
each has a `workflow_dispatch` run created 18:47–19:00 UTC (`gh api .../actions/runs?event=workflow_dispatch`).

## Cause

The scanner POSTs `actions/workflows/ci.yml/dispatches` with `{"ref":"main"}`. Order's `ci.yml` triggers only on
`push` and `pull_request` (`gh api repos/wilddog64/shopping-cart-order/contents/.github/workflows/ci.yml`, read
2026-11-22), so GitHub rejects the dispatch. Order has no `workflow_dispatch` runs in its history. The other four
mapped workflows each contain `workflow_dispatch` (grep count 2 each, same date).

The scanner runs curl with `--fail` and discards the response, so the log does not show the HTTP status.

## Impact

Order's HIGH/CRITICAL image CVEs are never rebuilt automatically; they persist until someone pushes to order's main.
Every daily scan retries and fails. The cache-clear step still runs first, so each failed attempt also deletes order's
Actions build caches (24 entries this run) without a rebuild to repopulate them.

## Fix direction

1. In `wilddog64/shopping-cart-order` `.github/workflows/ci.yml`, add `workflow_dispatch:` to `on:`, matching the
   product-catalog fix (`8e7b751a`, PR #65). Check that the build-push path runs on a dispatch event on `main`.
2. Optional, k3d-manager: log the HTTP status of a failed dispatch (without the response body or headers), and skip
   the cache clear when the workflow cannot be dispatched.

## Worker task (Luna, dispatched with `--repo <shopping-cart-order checkout> --branch fix/cve-manual-rebuild`)

In `wilddog64/shopping-cart-order`, branch `fix/cve-manual-rebuild` from `origin/main` (`00c9fcd`), edit only
`.github/workflows/ci.yml`:

1. Under `on:`, add `workflow_dispatch:` (no inputs) after the existing `pull_request` block. Keep `push` and
   `pull_request` exactly as they are.
2. Job `publish` (line 59 on `00c9fcd`): change
   `if: github.ref == 'refs/heads/main' && github.event_name == 'push'` to
   `if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')`.
   This is the product-catalog form (its `ci.yml` line 134, read via `gh api` 2026-11-22).

Change nothing else: not the `uses:` pin, permissions, secrets, other jobs or any other file. Commit on the branch;
do not push and do not open a PR (Claude does both after verification).

The local checkout is on `fix/automerge-app-token`, with its own work. Do not switch, stash or touch it. Work in a
separate `git worktree add` from `origin/main`, as the product-catalog precedent did. The local product-catalog
`origin/main` predates its fix, so read the precedent with `gh api repos/wilddog64/shopping-cart-product-catalog/contents/.github/workflows/ci.yml`.

## Files

- `.github/workflows/ci.yml` (in `wilddog64/shopping-cart-order`)

## Contract readers

- Writer of the dispatch: `scripts/etc/argocd/platform-ops/app-cve-scan.sh` `_build_workflow_for_service` maps
  `shopping-cart-order` to `ci.yml` and POSTs `actions/workflows/ci.yml/dispatches` with `{"ref":"main"}`; unchanged.
- Reader: GitHub Actions on order `main`; `publish` calls `shopping-cart-infra` `build-push-deploy.yml` at the pinned
  SHA (`542bb011`); unchanged. That workflow has no `event_name`/`ref` condition (Fable review 2026-11-22).
- Writes a dispatch run now also makes (unchanged behaviour, new trigger):
  - GHCR `ghcr.io/wilddog64/shopping-cart-order:latest` and `:sha-<head>` (reusable workflow 101-103). The scanner's
    candidate-image lookup reads them (`app-cve-scan.sh` ~440-450).
  - A `[skip ci]` promote commit to `k8s/base/kustomization.yaml` on order `main` via `PROMOTER_SSH_KEY` (reusable
    169-200). ArgoCD reads it.

## Acceptance

```yaml
must:
  - id: M1
    text: "order ci.yml declares workflow_dispatch under on:, with push and pull_request unchanged"
  - id: M2
    text: "the publish job runs on main for both push and workflow_dispatch events"
must_not:
  - id: N1
    text: "no file other than .github/workflows/ci.yml changes, and no other line of ci.yml changes"
  - id: N2
    text: "publish never runs for pull_request events or for a workflow_dispatch from a ref other than main"
  - id: N3
    text: "a workflow_dispatch event on main is not rejected by the workflow and does not skip publish"
evidence:
  - id: E1
    proves: [M1, M2, N2, N3]
    kind: offline
    intent: "You will see that order's CI now accepts a manual or scanner-triggered run, and that only main pushes and those runs publish an image, never a pull request or a run from another branch."
    how: "actionlint .github/workflows/ci.yml exits 0. python3 with PyYAML parses ci.yml (PyYAML reads the key on as True): the on: keys are exactly push, pull_request, workflow_dispatch; push and pull_request equal origin/main's. jobs.publish.if is evaluated as a truth table over (event, ref): (push, refs/heads/main) true; (workflow_dispatch, refs/heads/main) true; (pull_request, refs/pull/1/merge) false; (workflow_dispatch, refs/heads/other) false. Red controls: the same check on origin/main (00c9fcd) fails M1 and N3, and a mutant that drops the github.ref clause fails N2."
  - id: E2
    proves: [N1]
    kind: offline
    intent: "You will see the change is two lines in one file and nothing else in order's CI moved."
    how: "git diff --name-only origin/main...fix/cve-manual-rebuild is exactly .github/workflows/ci.yml; git diff --numstat shows exactly 2 added, 1 removed; every other line byte-identical."
  - id: E3
    proves: [M1, M2]
    kind: live
    intent: "After you merge, order gets rebuilt automatically: the next CVE scan (or one manual run) starts an order build on main that pushes a new image and promote commit, and the scan log no longer says the order rebuild failed."
    how: "Claude, read-only after the operator merges: gh api repos/wilddog64/shopping-cart-order/actions/runs?event=workflow_dispatch shows a run on main; actions/runs/<id>/jobs shows 'Build, Scan & Push / build-push' concluded success; a new 'ci: update shopping-cart-order to sha-<dispatched head>' commit is on main (or the sha-<head> tag exists in GHCR); the next app-cve-scan log on the hub has no 'shopping-cart-order: rebuild dispatch FAILED' line. Residual risk: build runs mvn verify with failBuildOnCVSS 9 (pom.xml:196), so a high-CVSS dependency can skip publish for an unrelated reason; if so, record it as a separate bug, not a failure of this fix."
interface:
  - "wilddog64/shopping-cart-order .github/workflows/ci.yml (on:, jobs.publish.if)"
  - "scripts/etc/argocd/platform-ops/app-cve-scan.sh dispatch POST (unchanged)"
```

## Fix and review 2026-11-22

- Luna (dispatch `order-ci-workflow-dispatch`) made the edit; its sandbox could not commit, so Claude committed it as
  `227bbdbe` on `fix/cve-manual-rebuild` and opened `wilddog64/shopping-cart-order` PR #109 (normal, not draft).
- Claude offline verification (E1, E2): `actionlint` exit 0; the `publish` condition gives main push → run, main
  dispatch → run, pull request → skip, dispatch from another branch → skip. Red controls: base `00c9fcd` fails M1 and
  N3; a mutant without the `refs/heads/main` clause fails N2. Diff: `ci.yml` only, +2 −1.
- Blind Argon review (`docs/plans/review-order-pr109-workflow-dispatch.md`, `gemini-4-argon-medium`): no findings;
  review worktree clean.
- PR #109 CI: Checkstyle, Build & Test, coverage, GitGuardian pass; `Build, Scan & Push` skipped on the pull request,
  live support for N2.
- Owed: operator merges; then Claude checks E3 (a dispatch run on main with build-push success and a promote commit;
  next scan without the FAILED line).

