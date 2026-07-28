#!/usr/bin/env bats

VALUES="${BATS_TEST_DIRNAME}/../../etc/argocd/values.yaml.tmpl"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"
TRIVY_DASH="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/trivy-security-configmap.yaml"

@test "metrics: serviceMonitor enabled for all four components" {
  run grep -cF -- 'serviceMonitor:' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 4 ]
}

@test "metrics: prometheus-operator discovery label present per component" {
  run grep -cF -- 'release: kube-prometheus-stack' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 4 ]
}

@test "metrics: dashboard ConfigMap carries grafana sidecar label" {
  run grep -F -- 'grafana_dashboard: "1"' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard targets monitoring namespace" {
  run grep -F -- 'namespace: monitoring' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard applied from argocd.sh platform-ops deploy" {
  run grep -F -- 'grafana-dashboard-argocd.yaml' "${PLUGIN}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard includes image updater deployment readiness panels" {
  run grep -F -- 'kube_deployment_status_replicas_available{namespace=\"cicd\",deployment=\"argocd-image-updater\"}' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'kube_deployment_spec_replicas{namespace=\"cicd\",deployment=\"argocd-image-updater\"}' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -cF -- '"textMode": "value"' "${DASH}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 2 ]
}

@test "metrics: dashboard focuses sync activity on watched apps and infra services" {
  run grep -F -- 'argocd_app_sync_total{name=~\"shopping-cart-(apps|basket|frontend|identity|namespace|networking|order|payment|product-catalog|rules)|data-layer|trivy-operator|ubuntu-hostinger-(eso|platform)\"}' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'argocd_app_info{name=~\"shopping-cart-(apps|basket|frontend|identity|namespace|networking|order|payment|product-catalog|rules)|data-layer|trivy-operator|ubuntu-hostinger-(eso|platform)\"}' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "alerts: argocd rules cover degraded, out-of-sync, and image flapping for watched apps" {
  RULE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/prometheusrule.yaml"

  run grep -F -- 'ArgoCDAppDegraded' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'ArgoCDAppOutOfSync' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'ArgoCDImageUpdaterFlapping' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'group: argocd' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'group: image-updater' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'name=~"shopping-cart-(apps|basket|frontend|identity|namespace|networking|order|payment|product-catalog|rules)|data-layer|trivy-operator|ubuntu-hostinger-(eso|platform)"' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'increase(argocd_app_sync_total{' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'name=~"shopping-cart-(basket|order|product-catalog)"' "${RULE}"
  [ "${status}" -eq 0 ]
}

@test "alerts: alertmanager routes argocd and image-updater alert names to the webhook analyzer" {
  ROUTE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/alertmanager-config.yaml"

  run grep -F -- 'value: ArgoCDAppDegraded|ArgoCDAppOutOfSync|ArgoCDImageUpdaterFlapping|TrivyOperatorScanJobFailures' "${ROUTE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'matchType: "=~"' "${ROUTE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'https://webhook.3ai-talk.org/api/v1/analyze' "${ROUTE}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard includes image-updater stat tiles from loki processing results" {
  run grep -F -- 'argocd-image-updater-hub.json' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'ArgoCD Apps & Image Updater Hub' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"uid": "argocd-image-updater-hub"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"uid": "loki"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'type": "loki"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Image Updater Apps Watched' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Images Updated (30d)' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Image Updater Errors (30d)' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| regexp \"applications=(?P<applications>\\\\d+)\" | unwrap applications [30d]' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| regexp \"errors=(?P<errors>\\\\d+)\" | unwrap errors [30d]' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"uid": "prometheus"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"templating": { "list": [] }' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard includes app-cve-scan job and decision visibility" {
  run grep -F -- 'App CVE Scan Successful Jobs' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'App CVE Scan Failed Jobs' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'App CVE Scan Decisions' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sum(increase(kube_job_status_succeeded{namespace=\"platform-ops\",job_name=~\"app-cve-scan.*\"}[30d])) or vector(0)' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"instant": true' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sum(increase(kube_job_status_failed{namespace=\"platform-ops\",job_name=~\"app-cve-scan.*\"}[30d])) or vector(0)' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '{namespace=\"platform-ops\",pod=~\"app-cve-scan.*\"} |= \"[app-cve-scan]\"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -cF -- '"timeFrom": "30d"' "${DASH}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 3 ]
}

@test "metrics: dashboard includes trivy infra security panels" {
  run grep -F -- 'Trivy Drilldown Banner' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'One row per High/Critical RBAC finding. The `source` column separates namespaced Roles (`rbac`) from cluster-scoped ClusterRoles (`clusterrole`). `Value` is the number of failing checks at that severity for that object, not the number of findings.' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra High/Critical Findings' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"title": "Open Trivy findings drilldown"' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"url": "?viewPanel=18"' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Cluster Compliance Failures' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc(sum by (title,description,status) (trivy_cluster_compliance{status=\"Fail\"}) > 0)' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra Findings Drilldown' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc((label_replace(label_replace(sum by (namespace,resource_name,resource_kind,severity) (trivy_role_rbacassessments{severity=~\"High|Critical\"}) > 0, \"source\", \"rbac\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review namespace-scoped permissions for this Role\", \"resource_name\", \".*\") or label_replace(label_replace(label_replace(label_replace(sum by (name,resource_kind,severity) (trivy_clusterrole_clusterrbacassessments{severity=~\"High|Critical\"}) > 0, \"resource_name\", \"$1\", \"name\", \"(.*)\"), \"namespace\", \"cluster\", \"\", \"\"), \"source\", \"clusterrole\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review cluster-wide permissions for this ClusterRole\", \"resource_name\", \".*\")))' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra High/Critical Findings' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy Cluster Compliance Failures' "${DASH}"
  [ "${status}" -ne 0 ]
}

@test "metrics: dashboard has exactly one trivy drilldown table and banner" {
  run grep -cF -- '### Trivy drilldown' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  run grep -F -- '### Trivy drilldown' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- '"title": "Trivy Drilldown",' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy Infra RBAC Drilldown' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy ClusterRole Drilldown' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- '"url": "?viewPanel=16"' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]
}

@test "metrics: dashboard banner uses real newlines not literal backslash-n" {
  run grep -F -- '\\n' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- '\\n' "${TRIVY_DASH}"
  [ "${status}" -ne 0 ]
}

@test "metrics: loki logs panel filters the app-cve-scan stream; other loki panels are stat/graph" {
  run grep -F -- '{namespace=\"platform-ops\",pod=~\"app-cve-scan.*\"} |= \"[app-cve-scan]\"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"showLabels": true' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -cF -- '"showLabels": false' "${DASH}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  run grep -F -- '| unwrap applications [30d]' "${DASH}"
  [ "${status}" -eq 0 ]
}
