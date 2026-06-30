#!/usr/bin/env bats

@test "cluster-status surfaces ArgoCD Image Updater health and activity" {
  run grep -nF '=== ArgoCD Image Updater ===' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'deploy/argocd-image-updater' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'Processing results:' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'Mode:' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'CVE-gated promotion controller active' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'argocd-image-updater\.argoproj\.io/image-list' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'Flapping' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'historical update churn remains in recent logs' bin/cluster-status
  [ "$status" -eq 0 ]
}
