#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/vault.sh"
  WATCHDOG_LOG="${BATS_TEST_TMPDIR}/watchdog.log"
  : > "${WATCHDOG_LOG}"
  _cleanup_on_success() { :; }
  envsubst() { command envsubst "$@"; }
}

@test "watchdog uses the target context for image lookup and apply" {
  _kubectl() {
    printf '_kubectl %s\n' "$*" >> "${WATCHDOG_LOG}"
    return 1
  }
  kubectl() {
    printf 'kubectl %s\n' "$*" >> "${WATCHDOG_LOG}"
    if [[ "$*" == *"get statefulset"* ]]; then
      printf '%s\n' "target.example/vault:target"
    else
      local manifest="${!#}"
      grep 'image:' "${manifest}" >> "${WATCHDOG_LOG}" || return 1
    fi
  }

  run vault_install_unseal_watchdog secrets ubuntu-hostinger
  [ "$status" -eq 0 ]
  run cat "${WATCHDOG_LOG}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubectl --context ubuntu-hostinger -n secrets get statefulset"* ]]
  [[ "$output" == *"image: target.example/vault:target"* ]]
  [[ "$output" != *"_kubectl"* ]]
}
