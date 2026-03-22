#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/system_overrides.sh"
}

teardown() {
  unset K3DM_DEPLOY_DRY_RUN
}

@test "dry-run prints command instead of executing" {
  export K3DM_DEPLOY_DRY_RUN=1
  run _run_command -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"echo"* ]]
  [[ "$output" != "hello" ]]
}

@test "dry-run with --prefer-sudo shows sudo prefix" {
  export K3DM_DEPLOY_DRY_RUN=1
  run _run_command --prefer-sudo -- apt-get update
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"sudo"* ]]
  [[ "$output" == *"apt-get"* ]]
}

@test "dry-run with --require-sudo shows sudo prefix" {
  export K3DM_DEPLOY_DRY_RUN=1
  run _run_command --require-sudo -- mkdir /etc/myapp
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"sudo"* ]]
  [[ "$output" == *"mkdir"* ]]
}

@test "normal mode executes command when K3DM_DEPLOY_DRY_RUN unset" {
  unset K3DM_DEPLOY_DRY_RUN
  run _run_command -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == "hello" ]]
}

@test "normal mode executes command when K3DM_DEPLOY_DRY_RUN=0" {
  export K3DM_DEPLOY_DRY_RUN=0
  run _run_command -- echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == "hello" ]]
}
