# Trivy Security (`trivy-security`) — ACG only

[← Grafana dashboards index](../grafana-dashboards.md)

Native `trivy-operator` metrics, no exporter in the path.

The hub **Grafana Health & Firing Alerts** dashboard also has a separate, bounded CVE findings
table. Its **Report created at (local)** value comes from the VulnerabilityReport object's
`metadata.creationTimestamp`; it is the report creation time, not the vulnerability's first
detection time. Both dashboard timestamps use the viewer's browser-local timezone. The general alert
table's `ALERTS_FOR_STATE` timestamp is **Active since** and
includes any pending interval (the Trivy alert rule uses `for: 15m`); it is not a CVE detection
or exact firing-start time. The aggregate category counts remain the alert-count view. The
active-instance table orders Namespace, Cluster, Alert, Category, available App/Pod/Instance
identity, Severity, Active since, and Elapsed time since active; it keeps per-alert instance timestamps
and does not synthesize pod identity. Elapsed time since active is elapsed alert active-state duration from
`ALERTS_FOR_STATE`, potentially including the pending period. It is not CVE age, time unpatched,
first-detection time, or exact firing-start time.

| Panel | Query basis |
|---|---|
| Trivy Scan Job Failures (30m) | `increase(kube_job_status_failed{namespace="trivy-system",job_name=~"scan-.*"}[30m])` |
| Trivy Infra High/Critical Findings | `trivy_role_rbacassessments` + `trivy_clusterrole_clusterrbacassessments` |
| Trivy Cluster Compliance Failures | `sort_desc(sum by (title,description,status) (trivy_cluster_compliance{status="Fail"}) > 0)` |
| Trivy Infra Findings Drilldown | the same, `label_replace`d twice to synthesise `source` / `reason` columns |
| Trivy Drilldown Banner | text panel |

Traps: `trivy-operator` **skips private images** unless
`operator.privateRegistryScanSecretsNames` is set, so a clean report can mean "not scanned"
(`memory/reference_trivy_operator_node_cred_private_image_skip.md`). The index-digest
verifier false-negative on multi-arch images is usually just aliasing
(`memory/reference_containerd_index_digest_aliasing_verifier.md`). And a reconcile panel
matching zero log lines is a query-drift bug that has happened before
(`docs/bugs/2026-07-24-trivy-reconcile-panel-query-matches-zero-lines.md`).
