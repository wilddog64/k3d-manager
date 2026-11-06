# Bug: Agent Activity repo gauges clip their values at nine rows

**Status:** LANDED `e631902b`, independent verify PASS 2026-11-06 (M1 to M3, N1, N2 pass; M1 and M3 red on the parent; 9 mutants red). Claude removed Luna's table pinning every panel's y, which would redden on any later dashboard edit. The 36 px row height is an estimate of Grafana's layout, so only the live E2 at Window 30d can confirm the panels are readable. Live E2 open
**Priority:** P3
**Severity:** low. The data is correct; on Window 30d the values cannot be read.
**Approval:** operator reported it 2026-11-06: "this became too crowdy to read for 30 d windows". Non-critical, Claude files and dispatches.
**Filed:** 2026-11-06
**Detected by:** operator, on the M5 Grafana, Agent Activity at Window 30d
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-01-agent-activity-repo-bar-gauges-lose-names-past-eight-rows.md` (capped the rows, kept the height; this is its failed live check), `docs/bugs/2026-10-24-agent-activity-titles-and-bar-labels-truncated.md` (same panels, earlier)

## Problem

Panels 54 "Untracked by repo" and 56 "Tokens by repo" in `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` are horizontal `bargauge` panels with `namePlacement: top`, `minVizHeight: 8`, `valueSize: 16` and `gridPos.h: 8`. The 2026-11-01 fix capped them at nine rows (top 8 plus `other`) but kept `h: 8`. At Window 30d all nine rows are present, so each row has roughly 28 px for a name line and a bar. The operator's screenshot shows the values cut in half (`204`, `3.07 Bil`) and each bar reduced to a thin line.

The existing test only asserts `h >= 5`, so it cannot catch this. This is the third report against these panels. Row count and height must be tested together.

## Fix

1. Set `gridPos.h` to 12 on all four panels in that row: 54, 55 "Sessions by mode", 56, and 57 "Codex active hours", so the row stays even.
2. Move every panel with `y >= 34` down by 4. No other `gridPos` changes.
3. Set `options.minVizHeight` to 36 on panels 54 and 56 only.
4. In `agent_dispatch_dashboard.bats`, replace the `h >= 5` assertion for those two panels with a row-height check: `(h * 38 - 8 - 52) / 9 >= 36`, where 38 px is one grid unit with its margin, and 52 px allows for the panel title and padding. Keep the query assertions. Update any test that pins the `y` of a moved panel, keeping its intent.

Do not change queries, legends, units, `namePlacement`, or any other panel's options.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "Panels 'Untracked by repo' and 'Tokens by repo' have gridPos.h of at least 12 and options.minVizHeight of at least 36."
  - id: M2
    text: "Every panel in the same grid row as those two has the same y and the same h, and no two panels in the dashboard overlap."
  - id: M3
    text: "Each panel's y is unchanged from the pre-fix dashboard if it was above y 34, and moved down by exactly the height increase otherwise, so the layout has no new gap (paired positive control for N1: the layout did change)."
must_not:
  - id: N1
    text: "No panel's targets, title, type, width, x, unit or transformations change, and only panels 'Untracked by repo' and 'Tokens by repo' change their options."
  - id: N2
    text: "Those two panels still cap at eight named rows plus one 'other' row, with namePlacement top."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2], kind: offline, text: "A test parsing the dashboard JSON from the YAML and comparing it against the pre-fix dashboard; M1 and M3 red on the pre-fix commit; N1 and N2 red by a mutant."}
  - {id: E2, proves: [M1], kind: live, text: "After the hub reads the release branch (make appsets-check, reapply if needed), the operator confirms at Window 30d on the M5 Grafana that every name and value on both panels can be read."}
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml, key agent-activity.json"
```
