#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/../.."
TEMPLATE="${ROOT}/etc/launchd/com.k3d-manager.hub-loki-port-forward.plist.tmpl"

@test "hub Loki port-forward targets loki-gateway on 19100" {
  run cat "${TEMPLATE}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"svc/loki-gateway"* ]]
  [[ "$output" == *"19100:80"* ]]
  [[ "$output" == *"monitoring"* ]]
  [[ "$output" == *"k3d-k3d-cluster"* ]]
}

@test "hub Loki make target renders and bootstraps the agent" {
  run make -n install-hub-loki-port-forward
  [ "$status" -eq 0 ]
  [[ "$output" == *"com.k3d-manager.hub-loki-port-forward.plist.tmpl"* ]]
  [[ "$output" == *"launchctl bootstrap"* ]]
}

@test "hub restore installs the Loki agent beside Pushgateway" {
  run grep -F -- 'install-hub-loki-port-forward' "${ROOT}/../bin/hub-restore"
  [ "$status" -eq 0 ]
}
