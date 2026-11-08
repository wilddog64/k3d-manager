# Bug: Plans panel shows a plan waiting on the operator's dispatch go as grey "not recorded"

**Status:** LANDED — fix and tests pushed on the release branch 2026-11-08; live once a second `make hub-promote` moves `deploy/hub` past it
**Priority:** P3
**Waiting on:** live check — since 2026-11-08
**Introduced by:** `608b90a1` (v1.43.9, the fix for `docs/bugs/2026-10-26-release-plans-dispatch-approval-unknown-despite-landed.md`, which chose the grey "not recorded" text)
**Should have been caught by:** spec
**Severity:** low — display only; the operator cannot tell from the Plans panel which plans wait on them
**Approval:** operator, 2026-11-08 ("make the values more obvious that need my approval instead of unknown")
**Filed:** 2026-11-08
**Detected by:** operator, Plans panel screenshot: "are last two waiting for my approval?"
**Affected:** `bin/k3dm-vectordb-metrics` (plan blockers, `dispatch_approval`), `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (panel 107 Plans), `docs/guides/grafana-dashboards/k3dm-bugs.md`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

For v1.43.15, the Plans rows "Checkout auto-sync" and "`control` role on Linux" showed Dispatch approval as
grey `not recorded`, with Blocked by `dispatch approval unknown`. Both plans were in fact waiting on the
operator's decision. The grey text read as missing data, not as a request for the operator.

## Fix

- Exporter blockers are worded for the operator: `needs your dispatch decision` (no `**Dispatch:**` header)
  and `needs your dispatch go` (`**Dispatch:** needed`).
- A plan past dispatch (landed or implemented) with no header reports `dispatch_approval="n/a"`, not `unknown`,
  so a missing header there no longer reads as pending.
- Panel 107, Dispatch approval: `unknown` → orange `⚠ needs your decision`, `needed` → orange `⚠ needs your go`,
  `go` → green `✓ go`, `not required` → `not gated`, `n/a` → `-`; `color-text` cells.
- Panel 107, Blocked by: `color-text` cells, a colour-only regex mapping `needs your dispatch` → orange.
- The two v1.43.15 plans now carry `**Dispatch:** needed`.

External behaviour, from Grafana source at tag `v11.4.0` (`gh api`, 2026-11-08): a `RegexToText` mapping with no
`result.text` returns the original text with only its colour
(`packages/grafana-data/src/utils/valueMappings.ts`; `displayProcessor.ts` keeps `text` when the mapping has
none); `color-text` is a table cell type (`packages/grafana-schema/src/common/common.gen.ts:697`).

## Evidence (offline, Claude's M4 session, 2026-11-08)

- `pytest scripts/tests/bin/test_vectordb_bug_metrics.py` → 118 passed, 2 skipped
- new test `test_missing_dispatch_header_reads_as_a_pending_decision_only_before_dispatch` against the `HEAD`
  exporter → fails at `"needs your dispatch decision" in rows[...]`
- `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` → 47/47, including two new tests: the orange
  mappings, and the exporter's blocker text matching the panel's highlight pattern

Live check after promote: the Plans panel shows the two v1.43.15 plans in orange as `⚠ needs your go`.
