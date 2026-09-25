#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  export SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/.local/share/k3d-manager"
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/lib/system.sh"
  # shellcheck source=/dev/null
  source "${PLUGINS_DIR}/ssm.sh"
}

@test "ssm_wait prints help with --help" {
  run ssm_wait --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ssm_wait"* ]]
}

@test "ssm_exec prints help with --help" {
  run ssm_exec --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ssm_exec"* ]]
}

@test "ssm_tunnel prints help with --help" {
  run ssm_tunnel --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ssm_tunnel"* ]]
}

@test "_ssm_get_instance_id returns error for unknown alias" {
  aws() { true; }
  export -f aws
  run _ssm_get_instance_id "bad-alias"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown node alias"* ]]
}

@test "ssm_exec fails when jq is absent" {
  _command_exist() { [[ "$1" != "jq" ]]; }
  export -f _command_exist
  run ssm_exec "i-abc123" "echo hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq is required"* ]]
}

@test "ssm_wait timeout returns 1 so callers can fall back" {
  run bash -c '
    export SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/plugins/ssm.sh
    aws() { echo "ConnectionLost"; }
    sleep() { return 0; }
    ssm_wait i-test || echo "REACHED_CALLER rc=$?"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not become Online after 300s"* ]]
  [[ "$output" == *"REACHED_CALLER rc=1"* ]]
}
