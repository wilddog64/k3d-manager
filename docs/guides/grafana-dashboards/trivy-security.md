# Trivy Security (`trivy-security`) — ACG only

[← Grafana dashboards index](../grafana-dashboards.md)

Native `trivy-operator` metrics, no exporter in the path.

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
