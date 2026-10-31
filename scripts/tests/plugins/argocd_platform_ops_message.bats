#!/usr/bin/env bats

@test "platform-ops: closing message reports current schedules" {
  local source="$BATS_TEST_DIRNAME/../../plugins/argocd.sh"
  run sed -n '/_info "\[argocd\] platform-ops deployed/,/^}/p' "$source"
  [ "$status" -eq 0 ]
  [[ "$output" == *'app CVE scan daily 01:00'* ]]
  [[ "$output" == *'ArgoCD CVE scan daily 01:30'* ]]
  [[ "$output" != *'1st+15th'* && "$output" != *'oci-kubeconfig'* ]]
}
