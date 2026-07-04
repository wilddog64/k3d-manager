#!/usr/bin/env bats

@test "cluster-status surfaces ArgoCD Image Updater section" {
  run grep -nF '=== ArgoCD Image Updater ===' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'deploy/argocd-image-updater' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'Processing results:' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status reports the new image updater mode" {
  run grep -nF 'Mode:' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'CVE-gated promotion controller active' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status explains idle historical churn" {
  run grep -nF 'Flapping' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'historical update churn remains in recent logs' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status still reports the App CVE Scan section" {
  run grep -nF '=== App CVE Scan ===' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'platform-ops' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'app-cve-scan' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status includes the Trivy Vulnerability Reports section" {
  run grep -nF '=== Trivy Vulnerability Reports ===' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'trivy_scan_report' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status includes the Trivy Infra Security section" {
  run grep -nF '=== Trivy Infra Security ===' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'trivy_infra_security_report' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status covers the watched shopping-cart apps in the CVE scan" {
  run grep -nF 'shopping-cart-frontend' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'shopping-cart-payment' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status documents immutable promotion output" {
  run grep -nF 'PROMOTION' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'rebuild dispatched' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'immutable sha-* candidate' bin/cluster-status
  [ "$status" -eq 0 ]
}
