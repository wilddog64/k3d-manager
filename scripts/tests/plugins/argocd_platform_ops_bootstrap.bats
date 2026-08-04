#!/usr/bin/env bats

@test "deploy_argocd_bootstrap invokes deploy_argocd_platform_ops" {
  run bash -c "awk '/^function deploy_argocd_bootstrap\\(\\)/,/^}\$/' scripts/plugins/argocd.sh | grep -c 'deploy_argocd_platform_ops'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "the platform-ops bootstrap call is guarded so it cannot abort the bootstrap" {
  run bash -c "awk '/^function deploy_argocd_bootstrap\\(\\)/,/^}\$/' scripts/plugins/argocd.sh | grep -F 'deploy_argocd_platform_ops || _warn'"
  [ "$status" -eq 0 ]
}

@test "platform-ops reconciliation applies the CVE inventory dashboard" {
  run grep -F -- 'grafana-dashboard-cve-autopatch.yaml' scripts/plugins/argocd.sh
  [ "$status" -eq 0 ]
}

@test "platform-ops reconciliation restarts exporter after ConfigMap updates" {
  run grep -F -- 'rollout restart deployment/vulnerability-inventory-exporter' scripts/plugins/argocd.sh
  [ "$status" -eq 0 ]
}
