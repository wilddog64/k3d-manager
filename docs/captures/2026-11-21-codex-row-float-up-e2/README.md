# Codex row float-up fix: E2 live capture (2026-11-21)

Bug: [`docs/bugs/2026-11-21-agent-activity-codex-row-panels-float-up.md`](../../bugs/2026-11-21-agent-activity-codex-row-panels-float-up.md)

- `make hub-deploy REF=42176488` (operator, 18:33Z): `deploy/hub 74ff9a6..4217648`, platform-ops ok.
- ArgoCD `hub-grafana-dashboards` synced the ConfigMap at 18:34:51Z. Claude, read-only: the live `monitoring/grafana-dashboard-agent-activity`
  equals the file at 42176488; 53/58/83 at y20 x0/8/16 w8 h6; 54-57 at y26 x0/6/12/18; the compaction simulation reports no moves
  (it reported 55, 56, 57 and 83 on the same live ConfigMap before the deploy).
- `agent-activity-codex-row.png` (operator screenshot): Untracked Codex sessions, Codex at API prices and Unpriced Codex sessions side by side;
  the four bar panels beneath. E2 PASS.
- Seen in the same screenshot, unrelated to this fix: a "Value" bar in Sessions by mode, filed as
  [`docs/bugs/2026-11-21-sessions-by-mode-value-bar-from-category-series.md`](../../bugs/2026-11-21-sessions-by-mode-value-bar-from-category-series.md).
