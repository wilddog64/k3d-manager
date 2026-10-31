#!/usr/bin/env bats
# scripts/tests/lib/k3d_install.bats
# _provider_k3d_install against a stub of the upstream k3d installer.

# shellcheck disable=SC1091

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  INSTALL_LOG="$BATS_TEST_TMPDIR/installer.log"
  BIN_DIR="$BATS_TEST_TMPDIR/home/.local/bin"
  mkdir -p "$BIN_DIR"
  [[ "$BIN_DIR" == "$BATS_TEST_TMPDIR"/* && "$BIN_DIR" != "$HOME/.local/bin" ]]
  export INSTALL_LOG
  PATH="/usr/bin:/bin"
  _command_exist() { command -v "$1" &> /dev/null; }
  _install_docker() { :; }
  _install_helm() { :; }
  _install_istioctl() { :; }
  _is_mac() { return 0; }
  # Contract of https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh, read 2026-10-30
  # (m4-air.local): ": ${USE_SUDO:="true"}", "runAsRoot cp ... $K3D_INSTALL_DIR/$APP_NAME",
  # then testVersion fails with "k3d not found. Is $K3D_INSTALL_DIR on your $PATH?".
  _curl() {
    cat <<'SH'
: "${USE_SUDO:=true}"
printf 'USE_SUDO=%s\nSUDO_PROMPT=%s\n' "$USE_SUDO" "$SUDO_PROMPT" >> "$INSTALL_LOG"
[ "$USE_SUDO" = false ] || { echo sudo-called >> "$INSTALL_LOG"; exit 1; }
printf '#!/bin/sh\necho k3d version v5.8.3\n' > "$K3D_INSTALL_DIR/k3d"; chmod +x "$K3D_INSTALL_DIR/k3d"
command -v k3d > /dev/null || { echo "k3d not found. Is $K3D_INSTALL_DIR on your \$PATH?"; exit 1; }
SH
  }
  source "${REPO_ROOT}/scripts/lib/providers/k3d.sh"
}

@test "installs into a writable dir off PATH without sudo and leaves k3d on PATH" {
  run bash -c '[[ ":$PATH:" == *":$1:"* ]]' _ "$BIN_DIR"
  [ "$status" -ne 0 ]
  set +e
  _provider_k3d_install "$BIN_DIR" > "$BATS_TEST_TMPDIR/out" 2>&1
  rc=$?
  set -e
  [ "$rc" -eq 0 ]
  grep -qx 'USE_SUDO=false' "$INSTALL_LOG"
  run grep -c sudo-called "$INSTALL_LOG"
  [ "$output" = 0 ]
  [ "$(command -v k3d)" = "$BIN_DIR/k3d" ]
}

@test "a dir the user cannot write still uses sudo, with a prompt naming the host" {
  ro="$BATS_TEST_TMPDIR/ro-bin"
  mkdir -p "$ro"; chmod 555 "$ro"
  set +e
  _provider_k3d_install "$ro" > /dev/null 2>&1
  set -e
  chmod 755 "$ro"
  grep -qx 'USE_SUDO=true' "$INSTALL_LOG"
  grep -q 'sudo-called' "$INSTALL_LOG"
  grep -qF 'SUDO_PROMPT=[sudo] password for %u on %H' "$INSTALL_LOG"
}

@test "an existing k3d on PATH is not reinstalled" {
  printf '#!/bin/sh\n' > "$BIN_DIR/k3d"; chmod +x "$BIN_DIR/k3d"
  _provider_k3d_install "$BIN_DIR" > /dev/null 2>&1
  [ ! -e "$INSTALL_LOG" ]
}
