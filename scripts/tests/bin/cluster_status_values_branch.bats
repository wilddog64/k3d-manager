#!/usr/bin/env bats

@test "cluster-status surfaces the ArgoCD Values-Branch Drift section" {
  run grep -nF '=== ArgoCD Values-Branch Drift' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status calls the drift detector through the dispatcher" {
  run grep -nF 'scripts/k3d-manager" argocd_check_values_branch' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status guards the drift check so set -e cannot abort the report" {
  run grep -nF '|| _vb_rc=$?' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status distinguishes drift, unreadable, and clean outcomes" {
  run grep -nF 'values-branch drift — reapply the sets' bin/cluster-status
  [ "$status" -eq 0 ]

  run grep -nF 'values-branch check skipped' bin/cluster-status
  [ "$status" -eq 0 ]
}

@test "cluster-status filters the dispatcher bash-version banner from the section" {
  run grep -nF "grep -vF 'running under bash version'" bin/cluster-status
  [ "$status" -eq 0 ]
}
