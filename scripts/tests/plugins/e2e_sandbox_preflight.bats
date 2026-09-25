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
  unset K3DM_ACG_REQUIRE_CREDENTIALS

  FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  export SECURITY_ARGS
  export ACG_FAKE_VALUE="${ACG_FAKE_VALUE:-tr0ubadour}"
  PATH="$FAKE_BIN:$PATH"
  export PATH

  _is_mac() { return 0; }
  _info() { printf '%s\n' "$*"; }
  _warn() { printf '%s\n' "$*"; }
  _err() { printf '%s\n' "$*"; return 1; }
  acg_extend_playwright() { : > "$EXTEND_CALLED"; }
  preflight_probe() {
    _e2e_sandbox_preflight_auth
    acg_extend_playwright "$_ACG_SANDBOX_URL"
  }
}

install_security() {
  cat > "$FAKE_BIN/security" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SECURITY_ARGS"
mode="${ACG_SECURITY_MODE:-readable}"
wants_value=0
for arg in "$@"; do
  [ "$arg" = "-w" ] && wants_value=1
done
case "$mode" in
  absent)
    exit 1
    ;;
  locked)
    if [ "$wants_value" -eq 1 ]; then
      printf 'security: SecKeychainSearchCopyNext: User interaction is not allowed.\n' >&2
      exit 1
    fi
    exit 0
    ;;
  empty)
    exit 0
    ;;
  password_only)
    case "$*" in
      *"-a password"*) exit 1 ;;
    esac
    ;;
esac
if [ "$wants_value" -eq 1 ]; then
  printf '%s' "$ACG_FAKE_VALUE"
fi
exit 0
FAKE
  chmod +x "$FAKE_BIN/security"
}

@test "preflight fails when _ACG_SANDBOX_URL is empty" {
  install_security
  unset _ACG_SANDBOX_URL
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"_ACG_SANDBOX_URL"* ]]
  run test -e "$EXTEND_CALLED"
  [ "$status" -ne 0 ]
}

@test "preflight refuses to run when K3DM_ACG_SKIP_SESSION_CHECK is set" {
  install_security
  export K3DM_ACG_SKIP_SESSION_CHECK=1
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"K3DM_ACG_SKIP_SESSION_CHECK=1"* ]]
}

@test "preflight reads no credential when it refuses on K3DM_ACG_SKIP_SESSION_CHECK" {
  install_security
  export K3DM_ACG_SKIP_SESSION_CHECK=1
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  run wc -c < "$SECURITY_ARGS"
  [ "$output" -eq 0 ]
}

@test "preflight fails when the credential entry is absent" {
  install_security
  export ACG_SECURITY_MODE=absent
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3dm-acg-pluralsight"* ]]
  [[ "$output" == *"unreadable=username,password"* ]]
}

@test "preflight fails when the entry exists but the login keychain is locked" {
  install_security
  export ACG_SECURITY_MODE=locked
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"credentials_loadable=false"* ]]
  [[ "$output" == *"unreadable=username,password"* ]]
  run test -e "$EXTEND_CALLED"
  [ "$status" -ne 0 ]
}

@test "preflight fails when the entry exists but the stored value is empty" {
  install_security
  export ACG_SECURITY_MODE=empty
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"credentials_loadable=false"* ]]
  [[ "$output" == *"unreadable=username,password"* ]]
}

@test "preflight still fails when the credential is unreadable but the profile dir EXISTS" {
  install_security
  export ACG_SECURITY_MODE=locked
  export PLAYWRIGHT_AUTH_DIR="$BATS_TEST_TMPDIR/live-pw-profile"
  mkdir -p "$PLAYWRIGHT_AUTH_DIR"
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"k3dm-acg-pluralsight"* ]]
  run test -e "$EXTEND_CALLED"
  [ "$status" -ne 0 ]
}

@test "preflight fails when only the username account is readable" {
  install_security
  export ACG_SECURITY_MODE=password_only
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" == *"unreadable=password"* ]]
  [[ "$output" != *"unreadable=username"* ]]
}

@test "preflight loads both credential accounts by name" {
  install_security
  run _e2e_sandbox_preflight_auth
  [ "$status" -eq 0 ]
  run grep -F -- "-a username" "$SECURITY_ARGS"
  [ "$status" -eq 0 ]
  run grep -F -- "-a password" "$SECURITY_ARGS"
  [ "$status" -eq 0 ]
}

@test "preflight leaks no credential value into its output" {
  install_security
  run _e2e_sandbox_preflight_auth
  [ "$status" -eq 0 ]
  [[ "$output" != *"$ACG_FAKE_VALUE"* ]]
}

@test "preflight prints no placeholder credential command" {
  install_security
  export ACG_SECURITY_MODE=absent
  run _e2e_sandbox_preflight_auth
  [ "$status" -ne 0 ]
  [[ "$output" != *"add-generic-password"* ]]
  [[ "$output" != *"<"* ]]
}

@test "preflight arms the fail-closed credential gate for the session check" {
  install_security
  _e2e_sandbox_preflight_auth
  [ "$K3DM_ACG_REQUIRE_CREDENTIALS" = "1" ]
}

@test "preflight arms the fail-closed gate as an exported variable" {
  install_security
  _e2e_sandbox_preflight_auth
  run bash -c 'printf "%s" "$K3DM_ACG_REQUIRE_CREDENTIALS"'
  [ "$output" = "1" ]
}

@test "preflight passes when url, credentials and env are all sane" {
  install_security
  export K3DM_ACG_SKIP_SESSION_CHECK=0
  run _e2e_sandbox_preflight_auth
  [ "$status" -eq 0 ]
  run preflight_probe
  [ "$status" -eq 0 ]
  [ -e "$EXTEND_CALLED" ]
}
