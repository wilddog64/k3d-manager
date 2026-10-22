# Bug: Active Alert Instances panel query has an unbalanced parenthesis

**Filed:** 2026-10-22 (Claude, from the operator's Grafana screenshot)
**Status:** OPEN
**Priority:** P3 — one dashboard panel shows an error; alert detection and delivery are unaffected
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "go ahead" to dispatching the panel-13 fix to Luna
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** Grafana Health & Firing Alerts dashboard (uid `k3dm-grafana-health`), panel id 13 "Active Alert Instances"
**Related:** `docs/bugs/2026-10-21-firing-alerts-dashboard-missing-start-time-and-age.md` (REOPENED; this
is the parse error behind its empty instance panel; that bug stays open for its live column check)

## Symptom

After `make platform-ops` on 2026-10-22, panel 13 shows Grafana's error icon and no rows, while the
aggregate "Firing Alerts by Category" panel shows 41 alerts.

## Root cause

Both targets of panel 13 open nine `label_replace(` calls but supply only eight `label_replace`
argument groups (`cluster`, then the seven `category` rules). The query therefore has one more `(`
than `)`:

| Target | `(` | `)` |
|---|---|---|
| A (`... * 1000`) | 11 | 10 |
| B (`time() - (...)`) | 13 | 12 |

Prometheus rejects the query as a parse error. The same text is in both dashboard copies. The
offline tests that passed for `28e74901` checked JSON shape and substrings, never that the PromQL
parses.

## Fix

- **F1.** In panel 13 of both files, remove one leading `label_replace(` from target A and from
  target B, so each has eight `label_replace(` and balanced parentheses. Change nothing else in the
  expressions.
- **F2.** Add a test to `scripts/tests/plugins/grafana_dashboard_appsets.bats` that, for every
  panel target `expr` in both overview-readable dashboard files, checks the parentheses balance
  (ignoring characters inside double-quoted strings) and that the number of `label_replace(` equals
  the number of `label_replace` argument groups. It must run without promtool, so it never skips.
  If `promtool` is on `PATH`, also check each panel-13 expr parses (`promtool query instant` is not
  usable offline; use a throwaway rules file with `promtool check rules`), skipping only that
  extra check when promtool is absent.
- **F3.** `CHANGELOG.md` entry.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml`
- `scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml`
- `scripts/tests/plugins/grafana_dashboard_appsets.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Both panel-13 targets in both dashboard files have balanced parentheses and parse as PromQL.
  - id: M2
    text: Panel 13 still returns one row per firing alert instance with the same category labels and the same A (ms timestamp) and B (seconds elapsed) semantics.
  - id: M3
    text: The two dashboard files carry identical panel-13 expressions.
must_not:
  - id: N1
    text: No panel target expr in either overview-readable dashboard may have unbalanced parentheses (red on the pre-fix files).
  - id: N2
    text: The balance check must not skip when promtool is absent.
  - id: N3
    text: No other panel, alert rule or exporter changes.
evidence:
  - id: E1
    proves: [M1, M3, N1, N2, N3]
    kind: offline
    text: bats scripts/tests/plugins/grafana_dashboard_appsets.bats; N1 red on the pre-fix dashboards; a mutation that adds one "(" to any panel expr turns it red.
  - id: E2
    proves: [M1, M2]
    kind: live
    text: After make platform-ops, the operator screenshots Grafana Health & Firing Alerts; panel 13 shows rows with no error icon and its row count is consistent with the aggregate panel.
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml (ConfigMap data JSON, panel id 13)
  - scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml (same panel)
  - scripts/tests/plugins/grafana_dashboard_appsets.bats
```

## Definition of Done

- [ ] F1–F3 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 shown red against the pre-fix dashboards.
- [ ] `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` green.
- [ ] Commit: `fix(grafana): balance the Active Alert Instances PromQL`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT run `make platform-ops` or touch the cluster.
- Do NOT restructure the query or the category rules; remove the extra `label_replace(` only.
