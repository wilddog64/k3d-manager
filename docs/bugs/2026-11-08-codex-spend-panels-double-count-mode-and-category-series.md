# Bug: Codex spend panels add the per-mode total to the per-category series, and show unpriced tokens as dollars

**Status:** LANDED — fix and tests pushed on the release branch 2026-11-08, after the `deploy/hub` bootstrap; live once a second `make hub-promote` moves `deploy/hub` past it
**Priority:** P2
**Waiting on:** live check — since 2026-11-08
**Introduced by:** `8153f9eb` (v1.43.15, Codex spend by session category)
**Should have been caught by:** offline test
**Severity:** medium — three cost readings are wrong: a phantom "Value" bar equal to the whole total, unpriced tokens drawn as `$49.1M`, the all-sessions total doubled, and the outside-dispatch share halved
**Approval:** operator, 2026-11-08 ("File P2, fix after bootstrap")
**Filed:** 2026-11-08
**Detected by:** operator, asking for readable labels on "Codex spend by category"; the other defects traced by Claude
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml` (panel 116 "Codex spend by category", "Spend outside dispatch"), `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` (panel 58 "Codex at API prices, all sessions")
**Branch:** `k3d-manager-v1.43.15`

## Symptom

Operator screenshot of Agent Cost, 2026-11-08 (hub Grafana 11.4.0), panel "Codex spend by category":

- bars `Value $51.6`, `dispatch $29.0`, `dispatch_unr… $1.31`, `exec_untrac… $0`, `interactive $21.3`, `other $0`,
  `+ codex-aut… $49.1M`
- the category labels are cut off under narrow vertical bars
- the panel description reads "contribute /opt/homebrew/bin/zsh until priced"

## Root cause

1. **Two series under one name.** `bin/k3dm-dispatch-metrics` emits `k3dm_codex_api_cost_usd` per `mode`
   (`:1953`, present before `8153f9eb`) and, since `8153f9eb`, per `category` (`:1899`, `:1901`). The categories
   split the same spend (a guardian review is charged to its parent, `:1878-1887`), so each set is a full copy.
   A selector that names neither label adds both:
   - panel 116, `sum by (category) (...)`: the mode series has no `category`, so it lands in one group with an
     empty label, which Grafana titles "Value". $51.6 = 29.0 + 1.31 + 0 + 21.3 + 0.
   - "Spend outside dispatch", denominator `sum(k3dm_codex_api_cost_usd{window="$window"})`: twice the
     spend, so the share reads half its real value.
   - Agent Activity panel 58, `sum(k3dm_codex_api_cost_usd{window="$window"})`: twice the spend.
2. **Tokens in dollars.** Target B (`k3dm_codex_unpriced_tokens`) inherits the panel unit `currencyUSD`, so
   49.1M tokens render as `$49.1M`.
3. **Description.** The `$0` in the description was expanded by a shell when written, to `$0` of the writer's zsh.
4. **Labels.** Seven vertical bars in a `w: 6` panel leave about 100px per name.

The tests pinned the double-counting expressions as written (`agent_dispatch_dashboard.bats:155`, `:843`,
`:852`), so they shared the defect.

## Fix

- Every `k3dm_codex_api_cost_usd` selector that sums across categories carries `category!=""`.
- Panel 116: `refId` A/B, an override `byFrameRefID: B` → `unit: short`, `orientation: horizontal`,
  `namePlacement: left`, the description restored with a literal `$0`.

External behaviour, read from Grafana source at tag `v11.4.0` (`gh api`, 2026-11-08): `byFrameRefID` is a field
matcher (`packages/grafana-data/src/transformations/matchers/ids.ts`); `BarGaugeNamePlacement` has `left`
(`packages/grafana-schema/src/common/common.gen.ts:659`); bargauge reads `namePlacement`
(`public/app/plugins/panel/bargauge/panelcfg.cue:40`).

## Evidence (offline, Claude's M4 session, 2026-11-08)

- `bats scripts/tests/plugins/agent_dispatch_dashboard.bats` → 46/46
- new tests "never add the mode and category series together" and "is readable and shows tokens as counts",
  against copies of the `HEAD` dashboards (`BASE=` scratch dir) → both `not ok`
- the guard, with only the activity file reverted, then only the cost file reverted → `not ok` each time

Live check after promote: the panel shows no "Value" bar, codex-auto-review as a token count, readable names;
panel 58 equals the sum of the category bars.
