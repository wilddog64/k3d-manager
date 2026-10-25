# Bug: Agent Dispatch Run outcomes labels truncate, and Per run evidence shows plumbing instead of tokens

**Status:** FIXED — offline-verified: dashboard BATS 18/18 (new test red on the pre-fix file), validate-manifests 83 valid. Live check pending the hub sync.
**Priority:** P3
**Severity:** low — the numbers are correct; the operator cannot read the outcome names, cannot open the spec, and never sees per-run tokens
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-24, by Claude, from the operator's screenshot 223
**Approval:** explicit 2026-10-24 ("can we just ech square length so that Run ous can show the full caption? … can you have hyperlink for slug? What is Value #A stand for?"). Not critical (one dashboard ConfigMap), fixed by Claude.
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
**Related:** `docs/bugs/2026-10-24-agent-activity-titles-and-bar-labels-truncated.md` (same bar gauge class on Agent Activity)

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Problem

On k3dm Agent Dispatch, row **Run outcomes and verified bug cost**:

1. **Run outcomes** (panel 43) is a bar gauge with the default orientation. Five vertical bars in a
   6-column panel print `accep…`, `progr…`, `unkno…`.
2. **Per run evidence** (panel 47) runs two instant table queries, outcome (A) and run tokens (B),
   with no transformation. Grafana shows frame A only, so the table has `Time`, `__name__`, `job`
   and `window` columns and `Value #A`. `Value #A` is the outcome series' sample value, a constant
   1 that only marks the series as present. The token column never appears: the frames differ on
   `__name__`, so a merge would not join them anyway.
3. The slug is plain text; there is no way to get from a row to its spec.

## Fix

1. Panel 43: `options.orientation: "horizontal"`, `options.namePlacement: "left"`.
2. Panel 47: both queries build a `doc` label with `label_join` and `label_replace`. A dated slug
   becomes `bugs/<slug>`, anything else `plans/<version>-<slug>`. Each query is then wrapped in
   `sum by` over the join labels, which drops `__name__`, `job` and `window`.
3. Transformations: `merge`, then `organize`. It hides `Time`, `__name__`, `job`, `window`, `doc`
   and `Value #A`, orders the columns version, slug, run, outcome, evidence, tokens, and renames
   `Value #B` to `Codex tokens`. Sort by slug.
4. A `slug` data link to
   `https://github.com/wilddog64/k3d-manager/blob/k3d-manager-${__data.fields.version}/docs/${__data.fields.doc}.md`.
5. **First-pass live verification** (panel 48) moves beside the table, like Last update beside
   Per spec: `x: 0`, `w: 6`, `h: 10` at the table's `y`; the table narrows to `x: 6`, `w: 18`. The
   panel stays a horizontal bar gauge with names on the left, with fixed text sizes (`titleSize`
   14, `valueSize` 24). Requested by the operator 2026-10-25 (screenshots 226, 227, 231): with
   auto-sized text the names grew so large that `pass` truncated to `p…`. A stat version was tried
   and rejected; the operator preferred the bars.
6. The pre-split fixture test exempts bar gauge orientation keys on every dashboard and panel 47,
   which the new test covers.

## Acceptance

```yaml
must:
  - id: M1
    text: Every Run outcomes bar shows its full outcome name.
  - id: M2
    text: Per run evidence shows one row per attempt with version, slug, run, outcome, evidence and Codex tokens.
  - id: M3
    text: Each slug opens its plan or bug spec on GitHub.
  - id: M4
    text: First-pass live verification sits left of Per run evidence on the same rows, with the same height, and shows each result name in full at a fixed font size.
must_not:
  - id: N1
    text: No raw plumbing column (Time, __name__, job, window, doc, Value #A) may be shown.
  - id: N2
    text: No other panel's targets, fieldConfig or options may change (the fixture test still guards them).
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2]
    text: agent_dispatch_dashboard.bats 18/18; the new test red on the pre-fix file; make validate-manifests passes.
  - id: E2
    kind: live
    proves: [M1, M2, M3, M4, N1]
    text: After the hub syncs, the operator's screenshot shows full outcome names, a Codex tokens column, and a slug link that opens the spec.
interface:
  - Grafana /d/k3dm-agent-dispatch
```
