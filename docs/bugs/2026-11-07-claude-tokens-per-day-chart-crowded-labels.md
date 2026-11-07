# Bug: "Claude tokens per day" and "Claude tokens per day by kind" are crowded: value labels and dates collide at 20+ days

**Status:** OPEN — run 2 implemented (Flash exited 2026-11-07; 2 files changed in its worktree, uncommitted); Claude verification and land next (panels 32 and 87, the rewritten 659-660 assertion and its mutation)
**Priority:** P3 (cosmetic: the numbers are right, the chart is hard to read)
**Waiting on:** fix running — since 2026-11-07
**Severity:** low
**Approval:** operator 2026-11-07: "yes, please go ahead with labe and tooltip changes + a P3 bug file and dispatch to Flash 3.8"
**Filed:** 2026-11-07
**Amended:** 2026-11-07, Claude — the operator reported both charts crowded (screenshot, 2026-11-07); Flash's first run stopped on a spec conflict: `agent_dispatch_dashboard.bats:659-660` asserts `valueSize >= 14` on panels 32 and 87 (added by v1.43.7 `d0c247dc` for readability), while this spec removed `valueSize` and forbade weakening assertions. Panel 32 added to scope; that assertion may be rewritten as stated in Fix.
**Detected by:** operator (reading Agent Cost on the hub, screenshot 2026-11-07)
**Release:** v1.43.15 (bug docs do not count toward the plan cap)
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml` panels 32 and 87
**Related:** `docs/bugs/2026-10-25-claude-tokens-per-day-no-cache-kind-breakdown.md` (added the panel);
`docs/bugs/2026-10-30-agent-cost-tokens-and-cost-by-kind-read-as-one-panel.md` (panels 86 and 88; not touched here)

## Symptom

Panel 32, "Claude tokens per day" (stacked by model), and panel 87, "Claude tokens per day by kind", are stacked bar charts over the last 30 days with identical options. At 20 days on 2026-11-07:

- Every bar carries a value label at a fixed 14 px (`"text": {"valueSize": 14}`). The labels crowd each other.
- The x-axis shows every full date (`2026-10-09`) horizontally with no skipping. Neighbours run together
  (`2026-10-152026-10-16`).

The panel will reach 30 bars, so this gets worse.

## Cause

The panel options were written when the chart had a few days of data: values always shown, unrotated tick labels,
no tick spacing. `date` is a string column built with `groupingToMatrix`, not a time field, so Grafana does not thin
the axis on its own the way it does for a time axis.

## Fix

In the `options` of panels 32 and 87 only:

- `"showValue": "never"`: no per-bar value labels.
- `"tooltip": {"mode": "multi", "sort": "desc"}`: hovering a bar lists every kind with its value.
- `"xTickLabelRotation": -45` and `"xTickLabelSpacing": 100`: tilted dates, and Grafana skips some when they do not fit.
- Remove `"text": {"valueSize": 14}`; it only sized the value labels.

Keep `"xField": "date"` and `"stacking": "normal"`. Do not change the target, the transformations, `fieldConfig`,
`gridPos`, the title or the description.

The existing assertion `for i in (32,87): assert cost[i]["options"]["text"]["valueSize"]>=14,i` (test
`agent dashboards: labels and titles stay readable and release-only stats say why they are empty`) guarded
readable value labels. Rewrite it, and only it, to keep that intent: for panels 32 and 87, if `showValue` is
not `never`, `options.text.valueSize` must be at least 14. Put `# agent-audit: allow assert-removed valueSize
guard made conditional on showValue, bug 2026-11-07-claude-tokens-per-day-chart-crowded-labels` on the
rewritten line.

A second panel for the non-cache kinds (cache_read is about 97% of each bar) is out of scope; the operator has not
decided on it.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml` (panels 32 and 87 `options` only)
- `scripts/tests/plugins/agent_dispatch_dashboard.bats` (extend the test
  `agent cost: daily Claude tokens and cost panels split by kind`, and rewrite the one valueSize assertion
  in `agent dashboards: labels and titles stay readable and release-only stats say why they are empty` as
  stated in Fix)

## What NOT to Do

- Do not touch any panel other than 32 and 87, including 86 and 88, or any other dashboard.
- Do not change the exporter (`bin/k3dm-dispatch-metrics`) or any metric.
- Do not remove or weaken an existing assertion, except the one valueSize assertion rewritten as stated in Fix. Add the new ones beside them.
- Write the new assertions first and show them red on the pre-fix tree.
- Do not run `make platform-ops`, touch the hub or Grafana, or call the Pushgateway.
- Do not edit CLAUDE.md, `memory-bank/` or `docs/roadmap.md`. Do not commit to `main`, create a PR or skip hooks.

## Acceptance

```yaml
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml: ConfigMap key agent-cost.json, panel ids 32 and 87"
  - "Grafana Agent Cost dashboard, panels 'Claude tokens per day' and 'Claude tokens per day by kind' (live)"
must:
  - id: M1
    text: "Panels 32 and 87 options each have showValue never, tooltip mode multi, xTickLabelRotation -45 and xTickLabelSpacing 100."
  - id: M2
    text: "Panels 32 and 87 each keep type barchart, xField date, stacking normal, its target expr and legendFormat, transformations, gridPos, title and description exactly as before."
must_not:
  - id: N1
    text: "Neither panel 32 nor 87 shows per-bar value labels: showValue is not 'always' or 'auto', and options.text.valueSize is absent (paired control: M1 reads showValue and finds 'never'). The rewritten readability assertion still fails a panel with showValue always and valueSize 10 (shown by a scratch mutation)."
  - id: N2
    text: "No panel other than 32 and 87 changes: the agent-cost JSON with the options of panels 32 and 87 removed is identical before and after the fix (paired control: M1 shows both panels did change)."
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    what: "bats scripts/tests/plugins/agent_dispatch_dashboard.bats; the new assertions red on the pre-fix tree; pytest scripts/tests/bin/test_dispatch_metrics.py still green."
  - id: E2
    proves: [M1, N1]
    kind: live
    what: "Operator or Claude, after make platform-ops: both charts show no value labels, the dates are tilted without running together, and hovering a bar lists every series (models on panel 32, the four kinds on panel 87)."
```
