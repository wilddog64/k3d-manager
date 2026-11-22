# Bug: order CI cannot accept the scanner's rebuild dispatch

**Status:** OPEN — captured 2026-11-22; triaged 2026-11-22 (operator: fix now, spec + Luna)
**Priority:** P2
**Introduced by:** pre-existing (order's `ci.yml` has never had a `workflow_dispatch` trigger)
**Should have been caught by:** spec — the 2026-10-27 product-catalog fix covered one repository and did not check the other app repositories
**Introducing change reviewed:** unknown
**Classified:** P2 by gemini-4-argon-medium, 2026-11-22 (Automated CVE rebuild dispatches for `shopping-cart-order` always fail and wipe its build cache because `.github/workflows/ci.yml` lacks `workflow_dispatch`, requiring a manual push to `main`.)
**Waiting on:** operator decision — since 2026-11-22 (intent approval for the Acceptance below)
**Triage:** patch → fix now in `wilddog64/shopping-cart-order` (operator 2026-11-22: "Fix now"; route "Spec + Luna"). The optional k3d-manager scanner part (Fix direction 2) carries to v1.46.0 as P3.
**Intent approved:** pending
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

## Files

- `.github/workflows/ci.yml` (in `wilddog64/shopping-cart-order`)

## Contract readers

- Writer of the dispatch: `scripts/etc/argocd/platform-ops/app-cve-scan.sh` `_build_workflow_for_service` maps
  `shopping-cart-order` to `ci.yml` and POSTs `actions/workflows/ci.yml/dispatches` with `{"ref":"main"}`; unchanged.
- Reader: GitHub Actions on order `main`; `publish` calls `shopping-cart-infra` `build-push-deploy.yml` at the pinned
  SHA; unchanged.

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
    text: "publish never runs for pull_request events (its if: still requires refs/heads/main and push or workflow_dispatch)"
evidence:
  - id: E1
    proves: [M1, M2, N2]
    kind: offline
    intent: "You will see that order's CI now accepts a manual or scanner-triggered run, and that only main pushes and those runs publish an image, never a pull request."
    how: "python3 with PyYAML (or yq) parses ci.yml on the branch: the on: keys (note PyYAML reads the key on as True) are exactly push, pull_request, workflow_dispatch; push and pull_request equal origin/main's; jobs.publish.if equals the M2 string. The same check run on origin/main (00c9fcd) fails M1 and M2."
  - id: E2
    proves: [N1]
    kind: offline
    intent: "You will see the change is two lines in one file and nothing else in order's CI moved."
    how: "git diff --name-only origin/main...fix/cve-manual-rebuild is exactly .github/workflows/ci.yml; git diff --numstat shows at most 2 added, 1 removed; every other line byte-identical."
  - id: E3
    proves: [M1, M2]
    kind: live
    intent: "After you merge, order gets rebuilt automatically: the next CVE scan (or one manual run) starts an order build on main that pushes a new image, and the scan log no longer says the order rebuild failed."
    how: "Claude, read-only after the operator merges: gh api repos/wilddog64/shopping-cart-order/actions/runs?event=workflow_dispatch shows a run on main whose publish job succeeded; the next app-cve-scan log on the hub has no 'shopping-cart-order: rebuild dispatch FAILED' line."
interface:
  - "wilddog64/shopping-cart-order .github/workflows/ci.yml (on:, jobs.publish.if)"
  - "scripts/etc/argocd/platform-ops/app-cve-scan.sh dispatch POST (unchanged)"
```

