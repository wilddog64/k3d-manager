# Bug: Agent dispatch "By model" shows No data, and "Ledger coverage" is titled with raw labels

**Status:** OPEN
**Priority:** P3
**Severity:** low — the totals are correct on the same row; one panel is blank, one is mislabelled
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude, from the operator's screenshot of the Cost (API-equivalent) row
**Approval:** explicit 2026-10-23. The operator said: "go ahead to dispatch P3".

**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (panels 24, 27)

## Problem

1. **By model (panel 27)** shows No data at window 30d. The exporter does produce
   `k3dm_dispatch_api_cost_by_model_usd{window,model}`: a local `--dry-run` on 2026-10-23 printed it
   for every window. Panel 27 is the only panel in the row whose target has no `"instant": true`. Its
   query is therefore a range query, while every working panel uses an instant query. That is the
   first thing to check, not a proven cause.
2. **Ledger coverage (panel 24)**: the first target has no `legendFormat`. Grafana titles the
   percentage with the series' raw labels, `{job="k3dm-dispatch", window="30d"}`. The second target
   is titled "outside the ledger".

## Fix

### F1. Panel 27

Make the target `"instant": true`, keep `legendFormat` `{{model}}`, and confirm with `promtool`
against a fixture that the expression returns one series per model. If the fixture shows that the
query is not the cause, stop and report what it shows. Do not guess a second change.

### F2. Panel 24

Give the first target `"legendFormat": "in the ledger"`.

## Tests

`scripts/tests/bin/test_dispatch_metrics.py`:

1. Panel 27's target is instant and its legend is `{{model}}`.
2. Panel 24's first target's legend is `in the ledger`; the second's is still `outside the ledger`.
3. A `promtool test rules` (or `promtool query` over a fixture TSDB) case, following
   `docs/bugs/2026-10-11-dispatch-dashboard-landing-success-no-data.md`: panel 27's expression over
   two models returns two series.

Show tests 1 and 2 red against the pre-fix dashboard.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: By model shows one bar per priced model for a time window.
  - id: M2
    text: Ledger coverage titles its percentage "in the ledger".
must_not:
  - id: N1
    text: No other panel, query, series or exporter output changes.
  - id: N2
    text: The "outside the ledger" value keeps its title, currencyUSD unit and 2 decimals.
evidence:
  - id: E1
    kind: offline
    proves: [M2, N1, N2]
    text: pytest scripts/tests/bin/test_dispatch_metrics.py green; tests 1-2 red on the pre-fix dashboard.
  - id: E2
    kind: offline
    proves: [M1]
    text: promtool shows panel 27's expression returning one series per model over the fixture.
  - id: E3
    kind: live
    proves: [M1, M2]
    text: After the Argo hard refresh, the operator's screenshot at window 7d shows By model bars for gpt-5.6-luna and gpt-6-luna, and coverage titled "in the ledger".
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml (panels 24 "Ledger coverage", 27 "By model")
  - series k3dm_dispatch_api_cost_by_model_usd{window,model}, k3dm_dispatch_codex_sessions{window,ledgered}
```

## Definition of Done

- [ ] F1–F2 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `pytest scripts/tests/bin/test_dispatch_metrics.py` green; paste the summary and the promtool output.
- [ ] Tests 1–2 shown red on a temp copy of the pre-fix dashboard.
- [ ] Commit: `fix(dispatch): show By model bars and title Ledger coverage`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT query the live Prometheus, Grafana or Pushgateway.
- Do NOT change `bin/k3dm-dispatch-metrics` or the price file.
- Do NOT modify files outside the Files list.
