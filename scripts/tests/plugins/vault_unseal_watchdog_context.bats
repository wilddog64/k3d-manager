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

@test "missing envsubst fails before apply" {
  local stub_bin="${BATS_TEST_TMPDIR}/no-envsubst"
  mkdir -p "$stub_bin"
  ln -s "$(command -v mktemp)" "$stub_bin/mktemp"
  unset -f envsubst
  _kubectl() { printf '%s\n' "$*" >> "$WATCHDOG_LOG"; }
  [ -d "$stub_bin" ] && [ ! -e "$stub_bin/envsubst" ]
  run bash -c 'PATH="$1"; command -v envsubst' _ "$stub_bin"
  [ "$status" -ne 0 ]
  PATH="$stub_bin" run vault_install_unseal_watchdog secrets
  [ "$status" -ne 0 ]
  [[ "$output" == *"envsubst not found on PATH"* ]]
  run grep -q 'apply' "$WATCHDOG_LOG"
  [ "$status" -ne 0 ]
}
