#!/usr/bin/env bats

VALUES="${BATS_TEST_DIRNAME}/../../etc/argocd/values.yaml.tmpl"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"

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

@test "metrics: dashboard includes a loki log panel for image-updater processing results" {
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

  run grep -F -- 'Image Updater Processing Results' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| json | line_format \"{{.log}}\" | regexp \"Processing results: applications=(?P<applications>\\\\d+) images_considered=(?P<images_considered>\\\\d+) images_skipped=(?P<images_skipped>\\\\d+) images_updated=(?P<images_updated>\\\\d+) errors=(?P<errors>\\\\d+)\" | line_format \"applications={{.applications}} images_considered={{.images_considered}} images_skipped={{.images_skipped}} images_updated={{.images_updated}} errors={{.errors}}\"' "${DASH}"
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
  run grep -F -- 'Trivy Drilldown Banner' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'The tables below now include a description/reason column for each High or Critical finding, and they only show active non-zero findings once, so the dashboard explains why each row is present.' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra High/Critical Findings' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"title": "Open Trivy findings drilldown"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"url": "?viewPanel=16"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Cluster Compliance Failures' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc(sum by (title,description,status) (trivy_cluster_compliance{status=\"Fail\"}) > 0)' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'description' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra RBAC Drilldown' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy ClusterRole Drilldown' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra Findings Drilldown' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc(label_replace(sum by (namespace,resource_name,resource_kind,severity) (trivy_role_rbacassessments{severity=~\"High|Critical\"}) > 0, \"reason\", \"Trivy RBAC finding: review namespace-scoped permissions for this Role\", \"resource_name\", \".*\"))' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc(label_replace(label_replace(sum by (name,resource_kind,severity) (trivy_clusterrole_clusterrbacassessments{severity=~\"High|Critical\"}) > 0, \"resource_name\", \"$1\", \"name\", \"(.*)\"), \"reason\", \"Trivy RBAC finding: review cluster-wide permissions for this ClusterRole\", \"name\", \".*\"))' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc((label_replace(label_replace(sum by (namespace,resource_name,resource_kind,severity) (trivy_role_rbacassessments{severity=~\"High|Critical\"}) > 0, \"source\", \"rbac\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review namespace-scoped permissions for this Role\", \"resource_name\", \".*\") or label_replace(label_replace(label_replace(label_replace(sum by (name,resource_kind,severity) (trivy_clusterrole_clusterrbacassessments{severity=~\"High|Critical\"}) > 0, \"resource_name\", \"$1\", \"name\", \"(.*)\"), \"namespace\", \"cluster\", \"\", \"\"), \"source\", \"clusterrole\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review cluster-wide permissions for this ClusterRole\", \"resource_name\", \".*\")))' "${DASH}"
  [ "${status}" -eq 0 ]
}
