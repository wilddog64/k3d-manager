#!/usr/bin/env bats

setup() {
  load '../test_helpers'
}

@test "node health watchdog starts an exited agent instead of skipping recovery" {
  run grep -F 'created|exited|paused) recovery_command="start"' \
    "${BATS_TEST_DIRNAME}/../../../bin/k3dm-node-health-watch"
  [ "$status" -eq 0 ]

  run grep -F '"${DOCKER_BIN:-docker}" "$recovery_command" "$node"' \
    "${BATS_TEST_DIRNAME}/../../../bin/k3dm-node-health-watch"
  [ "$status" -eq 0 ]
}

@test "node health watchdog preserves bounded recovery controls" {
  run grep -F 'threshold="${K3DM_NODE_RECOVERY_FAILURE_THRESHOLD:-5}"' \
    "${BATS_TEST_DIRNAME}/../../../bin/k3dm-node-health-watch"
  [ "$status" -eq 0 ]

  run grep -F 'cooldown="${K3DM_NODE_RECOVERY_COOLDOWN:-300}"' \
    "${BATS_TEST_DIRNAME}/../../../bin/k3dm-node-health-watch"
  [ "$status" -eq 0 ]
}
