# Bug: the Window dropdown on the Agent Dispatch and Agent Cost dashboards sorts releases alphabetically

**Status:** OPEN — `0a00bb39` (`sort: 8`) is live but inert on Grafana 11.4.0 (upstream scenes defect, fixed in Grafana 11.5.0); data-side fix specced and dispatched 2026-11-07 (operator: "go ahead with sorting on our side")
**Priority:** P3 (cosmetic: the dropdown order is wrong, every option still works)
**Waiting on:** fix running — since 2026-11-07
**Fixed upstream in:** Grafana 11.5.0 (bundles `@grafana/scenes` 5.36.4, which has `a5f78bee`); hub runs 11.4.0
**Severity:** low
**Approval:** operator 2026-11-07: "go ahead, but don't forget the file a bug for it too"
**Release:** v1.43.15 (bug docs do not count toward the plan cap)

## Symptom

The operator opened the Window variable on the Agent Dispatch dashboard (screenshot, 2026-11-07). The options read:

```
v1.43.2
v1.43.15
v1.43.14
v1.43.13
v1.43.12
v1.43.10
v1.43.0
7d
```

`v1.43.2` sits above `v1.43.15`. That is alphabetical descending order: as text, `"v1.43.2"` is greater than
`"v1.43.15"` because the character `2` is greater than `1`. The operator wants the releases in version order, which
is also date order, since releases are cut in sequence.

## Cause (partly unconfirmed)

Both dashboards define the variable as a Prometheus `label_values(k3dm_dispatch_landed, window)` query with
`"sort": 7`, Grafana's natural ascending sort, set since v1.43.5 (`401e4eca`, `61256041`):

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`

Natural ascending would list `7d, v1.43.0, v1.43.2, v1.43.10 … v1.43.15`. That is the wrong direction for the
operator's need (newest last), and it is also **not** what the hub shows. Prometheus returns label values in
ascending order, so ignoring the sort would not produce the descending list in the screenshot either. The running
Grafana version could not be read: the hub API was unreachable from the M4 (`127.0.0.1:55730` refused) when this was
filed. Whether this Grafana applies natural sort is therefore unproven, and the live check (E2) settles it.

The Agent Activity dashboard is not affected: its Window options are a fixed custom list (`1d,7d,30d`) shown in the
order written.

## Fix

Set `"sort": 8` (natural descending) on the Window variable of both dashboards. Expected order:
`v1.43.15, v1.43.14, v1.43.13, v1.43.12, v1.43.10, v1.43.2, v1.43.0, 7d`.

If E2 shows the order is still alphabetical, this Grafana does not apply natural sort, and the follow-up is to have
the exporter emit the windows in a form whose text order is version order. A change to the exporter is out of scope
here.

## Acceptance

```yaml
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml and grafana-dashboard-agent-cost.yaml: templating variable name=window"
  - "Grafana Agent Dispatch / Agent Cost dashboards, Window dropdown (live)"
must:
  - id: M1
    text: "The window variable on both dashboards has sort 8 (natural descending); type, query, label and the 7d default are unchanged."
must_not:
  - id: N1
    text: "Neither dashboard's window variable keeps an ascending or alphabetical sort (1, 2, 5, 6 or 7) (paired control: M1 reads the same field and finds 8)."
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    what: "bats agent_dispatch_dashboard.bats and pytest test_dispatch_metrics.py assert sort 8 on both dashboards; the new assertion is red on the pre-fix tree (sort 7)."
  - id: E2
    proves: [M1]
    kind: live
    what: "Operator or Claude, after make platform-ops from the release branch: the Window dropdown lists v1.43.15 first, v1.43.2 below v1.43.10, and 7d last."
```

## Triage 2026-11-07 (Claude)

`grafana-dashboards-hub` and three more ApplicationSets on the hub template `k3d-manager-v1.43.14`. The Window sort is invisible on the hub until `make appsets-reapply` runs from `k3d-manager-v1.43.15` (operator).

## Live check 2026-11-07 — FAILED (Claude, operator screenshots)

After the ApplicationSets were reapplied to `k3d-manager-v1.43.15`, the operator opened the Window dropdown on
`k3dm Agent Dispatch` twice, the second time after a hard reload. Both times it listed `1d, 30d, 7d, v1.43.0,
v1.43.10, v1.43.12, ...`, which is alphabetical. The config reached Grafana at every layer:

- ConfigMap `monitoring/grafana-dashboard-agent-dispatch` (ArgoCD `hub-grafana-dashboards`): `"sort": 8`.
- The sidecar file `/tmp/dashboards/agent-dispatch.json` in the Grafana pod: `"sort": 8`, written 23:21:29Z.
- Grafana API `/api/dashboards/uid/k3dm-agent-dispatch`: one dashboard, provisioned, updated 23:21:29Z, `"sort":8`.

**Cause: upstream.** Grafana 11.4.0 (`docker.io/grafana/grafana:11.4.0`) bundles `@grafana/scenes` 5.28.1 (its
`package.json` at tag `v11.4.0`). In scenes `packages/scenes/src/variables/variants/query/utils.ts` at `v5.28.1`,
`metricNamesToVariableValues` builds options as `{ label, value }` (line 54), but `sortByNaturalSort` compares
`a.text`/`b.text`. `text` is undefined on every option, so the comparator returns -1 for every pair and the list keeps
the datasource's order. Prometheus `label_values` returns that order alphabetically. `sortByNumeric` reads `opt.text`
too, so sorts 3, 4, 7 and 8 all have no effect on this Grafana. Only the alphabetical sorts (1, 2, 5, 6) read
`label`. The old `sort: 7` was equally inert, which is why the operator saw `1d, 30d, 7d`, not natural `1d, 7d, 30d`.
(Fetched by Claude with `gh api` from `grafana/grafana` at `v11.4.0` and `grafana/scenes` at `v5.28.1`, 2026-11-07.)

E1 passed because it asserts the JSON value, and the JSON is right. Only the live check could catch an upstream
defect, which is the reason E2 exists.

**Options (operator decision):**
1. **Data-side order.** The exporter publishes the order as a value (for example
   `k3dm_dispatch_window_order{window="v1.43.15"} 104315`), and the variable uses
   `query_result(sort_desc(...))` with a regex capturing `window`, and `sort: 0`, so Grafana keeps the query's order.
   This works on 11.4.0. Recommended.
2. **Upgrade Grafana** to a release whose scenes compares `label`. This is a larger change, and needs the fixed scenes
   version confirmed first.

## Fix (amended 2026-11-07 — data-side order; supersedes `## Fix` above)

Operator decision 2026-11-07: "go ahead with sorting on our side". Grafana must not do the sorting; the order comes
from the data.

1. `bin/k3dm-dispatch-metrics`: for every `window` value it emits on `k3dm_dispatch_landed`, also emit exactly one
   `k3dm_dispatch_window_order{window="<w>"} <n>`, where a higher `n` means listed earlier:
   - a release `vX.Y.Z`: `n = X*1000000 + Y*1000 + Z` (so `v1.43.15` = 1043015, above `v1.43.9` = 1043009);
   - the time windows rank below every release, in the order `1d` (3), `7d` (2), `30d` (1).
2. The Window variable on both dashboards (`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
   and `grafana-dashboard-agent-cost.yaml`): query `query_result(sort_desc(k3dm_dispatch_window_order))`, regex
   `/window="([^"]+)"/`, and `"sort": 0`. In Grafana 11.4.0, `0` is `VariableSort.disabled`
   (`packages/grafana-data/src/types/templateVars.ts` at `v11.4.0`), and scenes 5.28.1 `sortVariableValues` then
   returns the options in query order. Keep the variable's name, label, default (`current`) and refresh as they are.
3. Update `docs/guides/grafana-dashboards/` for each of the two dashboards (the Window variable): the order comes from
   `k3dm_dispatch_window_order` because Grafana 11.4.0 cannot natural-sort; on Grafana 11.5.0 or later a `sort`
   value would work, but the data-side order stays correct on either.

Expected order: `v1.43.15, v1.43.14, v1.43.13, v1.43.12, ..., v1.43.10, v1.43.9, ..., v1.43.0, 1d, 7d, 30d`.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- the two dashboard guides under `docs/guides/grafana-dashboards/` (name them in your final message)

## What NOT to do (amended fix)

- Do not use a `sort` value other than `0`; Grafana 11.4.0 applies none of the natural or numerical sorts.
- Do not rename `window` labels or zero-pad versions; every panel query filters on `window="$window"`.
- Do not change any other metric or panel.
- Two other open dispatches (`2026-11-07-bugs-dashboard-fix-running-not-checked-against-worker`,
  `2026-11-07-agy-dispatch-runs-have-no-api-equivalent-cost`) also edit `bin/k3dm-dispatch-metrics`. Keep your change
  local to where `k3dm_dispatch_landed` is emitted, so the three merge cleanly.
- Do not run git add, commit or push, and do not touch `memory-bank/`.

## Acceptance (amended fix)

```yaml
must:
  M1: for each window value on k3dm_dispatch_landed, the exporter emits exactly one k3dm_dispatch_window_order series with the value defined in the amended Fix
  M2: both dashboards' Window variable queries query_result(sort_desc(k3dm_dispatch_window_order)) with regex /window="([^"]+)"/ and sort 0
  M3: the guides explain where the order comes from and why
must_not:
  N1: v1.43.10 never ranks below v1.43.9, and v1.43.15 never ranks below v1.43.2 (red on the pre-fix exporter, which emits no order)
  N2: a window that is not on k3dm_dispatch_landed never gets an order series, so the dropdown shows no option without data (paired control for M1)
  N3: no time window ranks above a release
evidence:
  E1:
    proves: [M1, N1, N2, N3]
    kind: offline
    intent: >-
      You will see test_dispatch_metrics.py feed releases v1.43.0, v1.43.2, v1.43.9, v1.43.10, v1.43.15 and the three
      time windows, and assert the window_order values and the resulting descending order; red on the pre-fix exporter.
    what: python3 -m pytest scripts/tests/bin/test_dispatch_metrics.py
  E2:
    proves: [M2]
    kind: offline
    intent: >-
      You will see agent_dispatch_dashboard.bats assert the query, regex and sort 0 on both dashboards; red on the
      pre-fix dashboards (sort 8, label_values query).
    what: bats scripts/tests/plugins/agent_dispatch_dashboard.bats
  E3:
    proves: [M1, M2, N1]
    kind: live
    intent: >-
      After make platform-ops and with the ApplicationSets on the fix branch, the operator opens Window on k3dm Agent
      Dispatch and sees v1.43.15 first and 1d, 7d, 30d last.
    what: k3dm Agent Dispatch dashboard, Window dropdown
interface:
  - bin/k3dm-dispatch-metrics (Prometheus text output)
  - the Window variable in grafana-dashboard-agent-dispatch.yaml and grafana-dashboard-agent-cost.yaml
```
