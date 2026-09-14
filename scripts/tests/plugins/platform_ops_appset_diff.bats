#!/usr/bin/env bats

APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/platform-ops.yaml"
EXTERNALSECRET="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cluster-kubeconfig-externalsecret.yaml"

@test "platform-ops Application template enables server-side diff" {
  run awk '
    /^  template:/ { in_template = 1; next }
    in_template && /^    metadata:/ { in_metadata = 1; next }
    in_metadata && /^    spec:/ { exit }
    in_metadata { print }
  ' "${APPSET}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"argocd.argoproj.io/compare-options"* ]]
  [[ "$output" == *"ServerSideDiff=true"* ]]
}

@test "platform-ops ApplicationSet retains server-side apply" {
  run grep -F 'ServerSideApply=true' "${APPSET}"
  [ "$status" -eq 0 ]
}

@test "platform-ops ExternalSecret and ApplicationSet do not mask differences" {
  run grep -c 'ignoreDifferences' "${EXTERNALSECRET}"
  [ "$output" = "0" ]

  run grep -c 'ignoreDifferences' "${APPSET}"
  [ "$output" = "0" ]
}
