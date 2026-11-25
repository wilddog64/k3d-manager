#!/usr/bin/env bats
# Dispatch coverage for the pinned lib-foundation istioctl installer.
# shellcheck disable=SC2016,SC2030,SC2031

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  INSTALL_DIR="$BATS_TEST_TMPDIR/install"
  # Captured read-only on m2-air, 2026-11-23; see docs/bugs/2026-11-23-dr-drill-hub-up-istioctl-1-32-rejects-k3s-1-32.md.
  cat > "$BATS_TEST_TMPDIR/bin/istioctl" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == version ]]; then
  printf 'client version: 1.32.0\n'
fi
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/istioctl"
  for tool in curl tar; do
    cat > "$BATS_TEST_TMPDIR/bin/$tool" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "$TMPDIR/external-tools.log"
exit 1
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/$tool"
  done
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export INSTALL_DIR
  [[ "$INSTALL_DIR" == "$BATS_TEST_TMPDIR"/* && "$INSTALL_DIR" != "$HOME/.local/bin" ]]
}

@test "real dispatcher loads the pinned subtree installer" {
  local dispatcher_root="${DISPATCHER_ROOT:-$REPO_ROOT}"
  run env -i HOME="$BATS_TEST_TMPDIR/home" PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" \
    TMPDIR="$BATS_TEST_TMPDIR" bash "$dispatcher_root/scripts/k3d-manager" \
    _install_istioctl "$BATS_TEST_TMPDIR/install"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1.32.0"* ]]
  [[ "$output" != *"already exists, skip installation"* ]]
  [ ! -s "$BATS_TEST_TMPDIR/external-tools.log" ]
  [ "$(grep -c '_install_istioctl()' "$dispatcher_root/scripts/lib/core.sh" || true)" -eq 0 ]
  [ "$(grep -c '_install_istioctl()' "$dispatcher_root/scripts/lib/foundation/scripts/lib/core.sh")" -gt 0 ]
}

_assert_provider_refuses() {
  local provider="$1"
  local calls="$BATS_TEST_TMPDIR/istioctl-calls"
  run env INSTALL_DIR="$INSTALL_DIR" CALLS="$calls" PROVIDER_FILE="$REPO_ROOT/scripts/lib/providers/$provider.sh" \
    FOUNDATION_CORE="${FOUNDATION_CORE_OVERRIDE:-$REPO_ROOT/scripts/lib/foundation/scripts/lib/core.sh}" \
    LOCAL_CORE="${LOCAL_CORE_OVERRIDE:-$REPO_ROOT/scripts/lib/core.sh}" \
    bash -c '
      source "${PROVIDER_FILE%/lib/providers/*}/lib/foundation/scripts/lib/system.sh"
      source "$FOUNDATION_CORE"
      source "$LOCAL_CORE"
      _err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }
      _run_command() { while [[ "$1" != -- ]]; do shift; done; shift; "$@"; }
      _istioctl() { printf "%s\n" "$*" >> "$CALLS"; }
      _kubectl() { :; }
      SCRIPT_DIR="${PROVIDER_FILE%/lib/providers/*}"
      source "$PROVIDER_FILE"
      _provider_'"$provider"'_configure_istio dispatch-test
    '
  if [[ -s "$calls" ]]; then
    printf 'observed _istioctl calls: '
    cat "$calls"
  fi
  [ "$status" -ne 0 ]
  [ ! -s "$calls" ]
  [[ "$output" == *"1.32.0"* ]]
}

@test "k3d refuses mismatched istioctl before any Istio command" {
  _assert_provider_refuses k3d
}

@test "k3s refuses mismatched istioctl before any Istio command" {
  _assert_provider_refuses k3s
}
