#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  export SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/.ssh" "${HOME}/.kube"
  touch "${HOME}/.ssh/k3d-manager-key.pem"
  chmod 600 "${HOME}/.ssh/k3d-manager-key.pem"
  touch "${HOME}/.ssh/config"
  touch "${HOME}/.kube/config"
  export ACG_REGION="us-west-2"
  source "${SCRIPT_DIR}/lib/system.sh"
  source "${PLUGINS_DIR}/acg.sh"
}

@test "acg_provision prints help with --help" {
  run acg_provision --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: acg_provision"* ]]
}

@test "acg_provision requires --confirm" {
  run acg_provision
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires --confirm"* ]]
}

@test "acg_provision fails when aws credentials invalid" {
  _acg_check_credentials() { return 1; }
  run acg_provision --confirm
  [ "$status" -eq 1 ]
}

@test "acg_status prints help with --help" {
  run acg_status --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: acg_status"* ]]
}

@test "acg_status exits 1 when no instance found" {
  _acg_check_credentials() { return 0; }
  _acg_get_instance_id() { printf ''; }
  run acg_status
  [ "$status" -eq 1 ]
  [[ "$output" == *"No instance found"* ]]
}

@test "acg_extend prints help with --help" {
  run acg_extend --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: acg_extend"* ]]
}

@test "acg_extend opens browser on macOS" {
  uname() { echo "Darwin"; }
  _run_command() { echo "$*" >> "${BATS_TEST_TMPDIR}/run.log"; }
  export -f uname _run_command
  run acg_extend
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opening ACG sandbox page"* ]]
  grep -q "open" "${BATS_TEST_TMPDIR}/run.log"
}

@test "acg_extend prints URL on Linux" {
  uname() { echo "Linux"; }
  export -f uname
  run acg_extend
  [ "$status" -eq 0 ]
  [[ "$output" == *"${_ACG_SANDBOX_URL}"* ]]
}

@test "acg_teardown prints help with --help" {
  run acg_teardown --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: acg_teardown"* ]]
}

@test "acg_teardown requires --confirm" {
  run acg_teardown
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires --confirm"* ]]
}

@test "acg_teardown is idempotent when no stack found" {
  RUN_LOG="${BATS_TEST_TMPDIR}/run.log"
  _acg_check_credentials() { return 0; }
  _run_command() {
    local mode="$1"; shift
    echo "$mode $*" >> "$RUN_LOG"
    if [[ "$*" == aws\ cloudformation\ describe-stacks* ]]; then
      printf 'None'
    fi
    return 0
  }
  export -f _run_command
  run acg_teardown --confirm
  [ "$status" -eq 0 ]
  [[ "$output" == *"No CloudFormation stack found"* ]]
}

@test "acg_teardown deletes stack when found" {
  local stack_delete_log="${BATS_TEST_TMPDIR}/stack_delete"
  local stack_wait_log="${BATS_TEST_TMPDIR}/stack_wait"
  local kubectl_delete_log="${BATS_TEST_TMPDIR}/kubectl_delete"
  _acg_check_credentials() { return 0; }
  kubectl() { return 0; }
  _run_command() {
    local mode="$1"; shift
    if [[ "$*" == aws\ cloudformation\ describe-stacks* ]]; then
      printf 'CREATE_COMPLETE'
    elif [[ "$*" == aws\ cloudformation\ delete-stack* ]]; then
      touch "$stack_delete_log"
      echo "[stub] delete-stack"
    elif [[ "$*" == aws\ cloudformation\ wait\ stack-delete-complete* ]]; then
      touch "$stack_wait_log"
      echo "[stub] wait-delete"
    elif [[ "$*" == kubectl\ config\ delete-context* ]]; then
      touch "$kubectl_delete_log"
    fi
    return 0
  }
  export -f kubectl _run_command
  run acg_teardown --confirm
  [ "$status" -eq 0 ]
  [[ "$output" == *"[stub] delete-stack"* ]]
  [[ "$output" == *"[stub] wait-delete"* ]]
  [[ -f "$stack_delete_log" ]]
  [[ -f "$stack_wait_log" ]]
  [[ -f "$kubectl_delete_log" ]]
}
