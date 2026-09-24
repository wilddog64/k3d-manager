#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/e2e.sh"
  export _ACG_SANDBOX_URL="https://example.test/sandbox"
  export PLAYWRIGHT_AUTH_DIR="$BATS_TEST_TMPDIR/no-pw-profile"
  SECURITY_ARGS="$BATS_TEST_TMPDIR/security.args"
  EXTEND_CALLED="$BATS_TEST_TMPDIR/extend.called"
  : > "$SECURITY_ARGS"
  rm -f "$EXTEND_CALLED"
  security() {
    printf '%s\n' "$*" >> "$SECURITY_ARGS"
    return "${SECURITY_RC:-0}"
  }
  _info() { printf '%s\n' "$*"; }
  _warn() { printf '%s\n' "$*"; }
  _err() { printf '%s\n' "$*"; return 1; }
  acg_extend_playwright() { : > "$EXTEND_CALLED"; }
  preflight_probe() {
    _e2e_sandbox_preflight_auth
    acg_extend_playwright "$_ACG_SANDBOX_URL"
  }
}

@test "preflight fails when _ACG_SANDBOX_URL is empty" {
  unset _ACG_SANDBOX_URL
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"_ACG_SANDBOX_URL"* ]]
  run test -e "$EXTEND_CALLED"
  [ "$status" -ne 0 ]
}

@test "preflight fails when the keychain item is absent" {
  SECURITY_RC=1
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3dm-acg-pluralsight"* ]]
}

@test "preflight still fails when the keychain item is absent but the profile dir EXISTS" {
  SECURITY_RC=1
  export PLAYWRIGHT_AUTH_DIR="$BATS_TEST_TMPDIR/live-pw-profile"
  mkdir -p "$PLAYWRIGHT_AUTH_DIR"
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3dm-acg-pluralsight"* ]]
  run test -e "$EXTEND_CALLED"
  [ "$status" -ne 0 ]
}

@test "preflight refuses to run when K3DM_ACG_SKIP_SESSION_CHECK is set" {
  export K3DM_ACG_SKIP_SESSION_CHECK=1
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"K3DM_ACG_SKIP_SESSION_CHECK=1"* ]]
}

@test "preflight never passes -w to security" {
  run _e2e_sandbox_preflight_auth
  [ "$status" -eq 0 ]
  run grep -F -- "-w" "$SECURITY_ARGS"
  [ "$status" -ne 0 ]
}

@test "preflight prints no placeholder credential command" {
  SECURITY_RC=1
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" != *"add-generic-password"* ]]
  [[ "$output" != *"<"* ]]
}

@test "preflight passes when url, keychain item and env are all sane" {
  export K3DM_ACG_SKIP_SESSION_CHECK=0
  run _e2e_sandbox_preflight_auth
  [ "$status" -eq 0 ]
  run preflight_probe
  [ "$status" -eq 0 ]
  [ -e "$EXTEND_CALLED" ]
}
