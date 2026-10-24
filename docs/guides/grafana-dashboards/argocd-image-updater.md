# ArgoCD Apps & Image Updater Hub (`argocd-image-updater-hub`)

[← Grafana dashboards index](../grafana-dashboards.md)

Hub-only. Mixes three producers: kube-state-metrics, the ArgoCD ServiceMonitors, and
**Loki log queries**.

| Panel | Query basis | Producer |
|---|---|---|
| Image Updater Ready / Desired Replicas | `kube_deployment_status_replicas_available{namespace="cicd"}` | kube-state-metrics |
| Watched App Sync Activity (5m increase) | `increase(argocd_app_sync_total{...})` | ArgoCD ServiceMonitor |
| Watched App Health / Sync | `argocd_app_info{...}` | ArgoCD ServiceMonitor |
| Possible Flapping (30m syncs) | same, 30m window | ArgoCD ServiceMonitor |
| Image Updater Apps Watched / Images Updated (30d) / Errors (30d) | LogQL over `argocd-image-updater` pod logs, `\|= "Processing results"` + regexp unwrap | **promtail → Loki** |
| App CVE Scan Successful / Failed Jobs | `increase(kube_job_status_*{job_name=~"app-cve-scan.*"}[30d])` | kube-state-metrics |
| App CVE Scan Decisions | LogQL `\|= "[app-cve-scan]"` | **promtail → Loki** |
| Trivy Operator Job Reconcile Errors | LogQL `\| json \| level="error"` | **promtail → Loki** |

Three traps, all previously hit:

- **`argocd_*` is absent entirely if the ServiceMonitors never installed.** After the
  2026-09-10 hub rebuild, ArgoCD's Helm release was created *before* the ServiceMonitor CRD
  existed, so the chart's `Capabilities` check silently skipped all four ServiceMonitors
  even though `values` had `enabled: true`. Every `argocd_*` panel was blank with the values
  file looking correct. Recovery is `helm upgrade` with the same values — nothing in the
  config needs changing. Documented in
  `docs/bugs/2026-09-13-hub-rebuild-skips-argocd-servicemonitors-and-promtail.md`.
- **The Loki panels go blank when promtail is absent**, which the same rebuild also caused.
  These panels look identical to a broken query.
- **`Images Updated (30d)` nonzero is the alarm; `applications=0` is intended.** Image
  Updater legitimately reports `applications=0`. Do not "fix" it — see
  `memory/reference_image_updater_zero_applications.md`.

Two historical render bugs worth knowing, because the fix shape recurs: a LogQL panel with
`| json` but **no line filter** renders as a wall of promtail `kubernetes_*` labels rather
than message content, and a `30d`-window `increase()` panel goes blank when the dashboard
time picker is narrower than the window
(`docs/bugs/2026-07-10-loki-logs-panels-render-empty-and-raw-json.md`,
`docs/issues/2026-07-07-grafana-app-cve-panels-go-blank-on-7d-dashboard-range.md`). The
replica stat showing several `1`s instead of one is kube-state-metrics pod-IP churn across
restarts — cosmetic, fixed by wrapping in `max()`.
