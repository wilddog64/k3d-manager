#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/system_overrides.sh"
}

teardown() {
  unset DRY_RUN K3DM_DEPLOY_DRY_RUN
}

@test "canonical DRY_RUN disables commands and activates predicate" {
  export DRY_RUN=1
  run _dry_run_active
  [ "$status" -eq 0 ]
  run _run_command -- touch "$BATS_TEST_TMPDIR/canonical"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/canonical" ]
}

@test "legacy K3DM_DEPLOY_DRY_RUN remains a compatible alias" {
  export K3DM_DEPLOY_DRY_RUN=1
  run _dry_run_active
  [ "$status" -eq 0 ]
  run _run_command -- touch "$BATS_TEST_TMPDIR/legacy"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/legacy" ]
}

@test "dry-run predicate is inactive when both flags are unset or zero" {
  DRY_RUN=0 K3DM_DEPLOY_DRY_RUN=0 run _dry_run_active
  [ "$status" -ne 0 ]
  unset DRY_RUN K3DM_DEPLOY_DRY_RUN
  run _dry_run_active
  [ "$status" -ne 0 ]
}

@test "dry-run prints command instead of executing" {
  export K3DM_DEPLOY_DRY_RUN=1
  run _run_command -- touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"touch"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
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
