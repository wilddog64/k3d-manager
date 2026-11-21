# plan-quotas E2, 2026-11-21

Hub m5-air, deploy/hub 74ff9a6f (contains bd5e4828). Screenshots by the operator (Grafana, signed in) at about 15:25Z;
Prometheus reads by Claude 15:21:48Z (read-only, `kube-prometheus-stack-prometheus` via the API proxy on `k3d-k3d-cluster`).

- Live ConfigMaps `monitoring/grafana-dashboard-agent-cost` and `-agent-activity` equal the deploy/hub YAML (jq -S compare).
- `agent-cost-plan-quotas.png`: row Plan quotas: Fable tokens per day, Fable weekly 8%, Claude weekly 14.0%, Claude 5h 9%, Codex weekly
  21%, Codex 5h 32%, each with a reset time; reading ages Claude 10.2 min, Codex 8.29 h.
- Prometheus: claude used five_hour 0.09, seven_day 0.14, weekly_fable 0.08 (resets 16:30Z today, 2026-11-26 22:00Z both weekly);
  codex primary 0.32, secondary 0.21 (resets 11:06:20Z today, already past, and 2026-11-28 01:06Z); Fable daily token series 10.
- `agent-activity-codex-row.png`: row All Codex activity has its panels with no gap where the quota stats were.
- Note: the Codex 5h gauge shows the last reading (8.3 h old, reset already passed); the reading-age panel flags it. Not an E2 defect.
