# Bug: order CI cannot accept the scanner's rebuild dispatch

**Status:** OPEN — captured 2026-11-22, not triaged
**Priority:** P2
**Introduced by:** pre-existing (order's `ci.yml` has never had a `workflow_dispatch` trigger)
**Should have been caught by:** spec — the 2026-10-27 product-catalog fix covered one repository and did not check the other app repositories
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-22
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
