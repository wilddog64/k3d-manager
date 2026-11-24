#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329

_err() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

setup() {
  unset ISTIOCTL_CURL_FAIL ISTIOCTL_TAR_FAIL ISTIOCTL_MKDIR_FAIL_PATH ISTIOCTL_CP_FAIL_PATH
  CORE_LIB="${BATS_TEST_DIRNAME}/../../lib/core.sh"
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  INSTALL_DIR="${BATS_TEST_TMPDIR}/install"
  mkdir -p "$STUB_BIN" "$INSTALL_DIR"
  export CORE_LIB STUB_BIN INSTALL_DIR
  export ISTIOCTL_URL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  export TEST_TMP_ROOT="$BATS_TEST_TMPDIR"
  export ISTIOCTL_TMP_LOG="${BATS_TEST_TMPDIR}/mktemp.log"
  export ISTIOCTL_CHECKSUM_MODE="valid"
  : > "$ISTIOCTL_URL_LOG"
  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' "${TEST_UNAME_S:-Darwin}" ;;
  -m) printf '%s\n' "${TEST_UNAME_M:-arm64}" ;;
  *) exit 1 ;;
esac
EOF
  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/sh
url=""
for arg do
  case "$arg" in http://*|https://*) url="$arg" ;; esac
done
printf '%s\n' "$url" >> "$ISTIOCTL_URL_LOG"
case "$url" in
  */istioctl-*.tar.gz)
    [ "${ISTIOCTL_CURL_FAIL:-0}" = 1 ] && exit 8
    out=""
    previous=""
    for arg do
      if [ "$previous" = "-o" ]; then out="$arg"; fi
      previous="$arg"
    done
    cp "$ISTIOCTL_FIXTURE" "$out"
    ;;
  *) exit 92 ;;
esac
EOF
  cat > "$STUB_BIN/shasum" <<'EOF'
#!/bin/sh
[ "$1" = "-a" ] && [ "$2" = "256" ] || exit 97
[ -f "$3" ] && [ "${3##*/}" = "istioctl.tar.gz" ] || exit 97
if [ "$ISTIOCTL_CHECKSUM_MODE" = mismatch ]; then
  printf '%s  %s\n' bad "$3"
else
  printf '%s  %s\n' "$ISTIOCTL_EXPECTED_SHA" "$3"
fi
EOF
  cat > "$STUB_BIN/rm" <<'EOF'
#!/bin/sh
for arg do
  case "$arg" in /tmp/istio-*) exit 0 ;; esac
done
exec /bin/rm "$@"
EOF
  chmod +x "$STUB_BIN/uname" "$STUB_BIN/curl" "$STUB_BIN/shasum" "$STUB_BIN/rm"
  cat > "$STUB_BIN/mktemp" <<'EOF'
#!/bin/sh
dir="${TEST_TMP_ROOT}/worktmp"
/bin/rm -rf "$dir"
/bin/mkdir -p "$dir"
printf '%s\n' "$dir" > "$ISTIOCTL_TMP_LOG"
printf '%s\n' "$dir"
EOF
  cat > "$STUB_BIN/tar" <<'EOF'
#!/bin/sh
[ "${ISTIOCTL_TAR_FAIL:-0}" = 1 ] && exit 9
exec /usr/bin/tar "$@"
EOF
  cat > "$STUB_BIN/mkdir" <<'EOF'
#!/bin/sh
case "$*" in *"${ISTIOCTL_MKDIR_FAIL_PATH:-__no_match__}"*) exit 10 ;; esac
exec /bin/mkdir "$@"
EOF
  cat > "$STUB_BIN/cp" <<'EOF'
#!/bin/sh
case "$*" in *"${ISTIOCTL_CP_FAIL_PATH:-__no_match__}"*) exit 11 ;; esac
exec /bin/cp "$@"
EOF
  chmod +x "$STUB_BIN/mktemp" "$STUB_BIN/tar" "$STUB_BIN/mkdir" "$STUB_BIN/cp"
  export PATH="$STUB_BIN:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
  export ISTIOCTL_EXPECTED_SHA=2be63df4a0fedb10c9c5402cdbf2f666e84330f3c68aef244975225ea63ef675
  _make_fixture
}

teardown() {
  chmod -R u+w "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

_make_fixture() {
  local fixture_dir="${BATS_TEST_TMPDIR}/fixture"
  mkdir -p "$fixture_dir"
  cat > "$fixture_dir/istioctl" <<'EOF'
#!/bin/sh
# Captured client version format from m4-air, m2-air, and m5-air (2026-11-23).
printf '%s\n' 'client version: 1.31.4'
EOF
  chmod +x "$fixture_dir/istioctl"
  tar -czf "${BATS_TEST_TMPDIR}/istioctl.tar.gz" -C "$fixture_dir" istioctl
  export ISTIOCTL_FIXTURE="${BATS_TEST_TMPDIR}/istioctl.tar.gz"
}

_write_existing() {
  local path="$1" line="$2" mode="${3:-stdout}"
  mkdir -p "${path%/*}"
  if [ "$mode" = stderr ]; then
    printf '#!/bin/sh\nprintf "%%s\\n" "%s" >&2\n' "$line" > "$path"
  else
    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$line" > "$path"
  fi
  chmod +x "$path"
}

@test "pin table returns the four published checksums and rejects unknown platforms" {
  source "$CORE_LIB"
  [ "$(_istioctl_pinned_sha256 1.31.4 osx arm64)" = 2be63df4a0fedb10c9c5402cdbf2f666e84330f3c68aef244975225ea63ef675 ]
  [ "$(_istioctl_pinned_sha256 1.31.4 osx amd64)" = da2398901943b3718566ca59311e045a0d99089006394fb573f34c23cd720311 ]
  [ "$(_istioctl_pinned_sha256 1.31.4 linux amd64)" = 7c00227d87f280c2450483e3518e3a73af62c057363b779ea80931c409e8852e ]
  [ "$(_istioctl_pinned_sha256 1.31.4 linux arm64)" = 3a1a82af8788059192d411e92d952c32d31a69bc20a039b3915f536d395e0c24 ]
  ! _istioctl_pinned_sha256 1.32.0 osx arm64
  ! _istioctl_pinned_sha256 1.31.4 freebsd arm64
}

@test "downloads the pinned archive on macOS arm64 and installs it" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]
  [ "$(command -v istioctl 2>/dev/null || true)" = "" ]
  source "$CORE_LIB"
  _run_command() { while [ "$1" != "--" ]; do shift; done; shift; "$@"; }
  _install_istioctl "$INSTALL_DIR"
  [ -x "$INSTALL_DIR/istioctl" ]
  [ "$(cat "$ISTIOCTL_URL_LOG")" = "https://github.com/istio/istio/releases/download/1.31.4/istioctl-1.31.4-osx-arm64.tar.gz" ]
  [[ "$($INSTALL_DIR/istioctl)" == "client version: 1.31.4" ]]
}

@test "downloads the pinned archive for macOS amd64" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]
  export TEST_UNAME_M=x86_64 ISTIOCTL_EXPECTED_SHA=da2398901943b3718566ca59311e045a0d99089006394fb573f34c23cd720311
  [ "$(command -v istioctl 2>/dev/null || true)" = "" ]
  source "$CORE_LIB"; _run_command() { while [ "$1" != "--" ]; do shift; done; shift; "$@"; }
  _install_istioctl "$INSTALL_DIR"
  [ -x "$INSTALL_DIR/istioctl" ]
  [[ "$(cat "$ISTIOCTL_URL_LOG")" == */istioctl-1.31.4-osx-amd64.tar.gz ]]
}

@test "downloads the pinned archive for Linux amd64 and arm64" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]
  export TEST_UNAME_S=Linux TEST_UNAME_M=x86_64 ISTIOCTL_EXPECTED_SHA=7c00227d87f280c2450483e3518e3a73af62c057363b779ea80931c409e8852e
  [ "$(command -v istioctl 2>/dev/null || true)" = "" ]
  source "$CORE_LIB"; _run_command() { while [ "$1" != "--" ]; do shift; done; shift; "$@"; }
  _install_istioctl "$INSTALL_DIR"
  [ -x "$INSTALL_DIR/istioctl" ]
  [[ "$(cat "$ISTIOCTL_URL_LOG")" == */istioctl-1.31.4-linux-amd64.tar.gz ]]
  rm -f "$INSTALL_DIR/istioctl"; : > "$ISTIOCTL_URL_LOG"
  export TEST_UNAME_M=aarch64 ISTIOCTL_EXPECTED_SHA=3a1a82af8788059192d411e92d952c32d31a69bc20a039b3915f536d395e0c24
  _install_istioctl "$INSTALL_DIR"
  [ -x "$INSTALL_DIR/istioctl" ]
  [[ "$(cat "$ISTIOCTL_URL_LOG")" == */istioctl-1.31.4-linux-arm64.tar.gz ]]
}

@test "accepts same-minor PATH and install_dir binaries without downloading" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]
  source "$CORE_LIB"; _run_command() { shift; "$@"; }
  _write_existing "$STUB_BIN/istioctl" 'client version: 1.31.1'
  [ "$(command -v istioctl)" = "$STUB_BIN/istioctl" ]
  run _install_istioctl "$INSTALL_DIR"
  [ "$status" -eq 0 ]; [[ "$output" == *"1.31.1"* && "$output" == *"1.31.4"* ]]
  [ ! -s "$ISTIOCTL_URL_LOG" ]
  rm "$STUB_BIN/istioctl"
  _write_existing "$INSTALL_DIR/istioctl" 'client version: 1.31.4'
  [ "$(command -v istioctl 2>/dev/null || true)" = "" ]
  run _install_istioctl "$INSTALL_DIR"
  [ "$status" -eq 0 ]; [[ "$output" == *"1.31.4"* ]]
  [ ! -s "$ISTIOCTL_URL_LOG" ]
}

@test "refuses another minor and malformed or stderr-only version output" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]
  source "$CORE_LIB"
  for line in 'client version: 1.32.0' 'client version: 1.30.0' '1.32.0'; do
    _write_existing "$STUB_BIN/istioctl" "$line"
    [ "$(command -v istioctl)" = "$STUB_BIN/istioctl" ]
    run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\\n" "$*" >&2; exit 1; }; _install_istioctl "$INSTALL_DIR"' 
    [ "$status" -ne 0 ]
    [[ "$output" == *"$STUB_BIN/istioctl"* && "$output" == *"1.31.4"* && "$output" == *"brew unlink istioctl"* && "$output" == *"ISTIOCTL_VERSION"* && "$output" == *"releases"* ]]
    rm "$STUB_BIN/istioctl"
  done
  _write_existing "$STUB_BIN/istioctl" 'client version: 1.31.4' stderr
  [ "$(command -v istioctl)" = "$STUB_BIN/istioctl" ]
  run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\\n" "$*" >&2; exit 1; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -ne 0 ]; [[ "$output" == *"unknown"* && "$output" == *"$STUB_BIN/istioctl"* ]]
}

@test "ISTIOCTL_VERSION override accepts existing matching minor and refuses unsupported download" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]
  _write_existing "$STUB_BIN/istioctl" 'client version: 1.32.0'
  [ "$(command -v istioctl)" = "$STUB_BIN/istioctl" ]
  run env ISTIOCTL_VERSION=1.32.0 bash -c 'source "$CORE_LIB"; _run_command() { while [ "$1" != "--" ]; do shift; done; shift; "$@"; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -eq 0 ]; [[ "$output" == *"1.32.0"* ]]
  [ ! -s "$ISTIOCTL_URL_LOG" ]
  rm "$STUB_BIN/istioctl"
  [ "$(command -v istioctl 2>/dev/null || true)" = "" ]
  run env ISTIOCTL_VERSION=1.32.0 bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\\n" "$*" >&2; exit 1; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -ne 0 ]; [[ "$output" == *"no pinned checksum for 1.32.0-osx-arm64"* ]]
  [ ! -s "$ISTIOCTL_URL_LOG" ]
}

@test "checksum mismatch refuses installation without copying a binary" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]
  [ "$(command -v istioctl 2>/dev/null || true)" = "" ]
  export ISTIOCTL_CHECKSUM_MODE=mismatch
  run bash -c 'source "$CORE_LIB"; _run_command() { while [ "$1" != "--" ]; do shift; done; shift; "$@"; }; _err() { printf "ERROR: %s\\n" "$*" >&2; exit 1; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -ne 0 ]; [[ "$output" == *"checksum"* ]]
  [ ! -e "$INSTALL_DIR/istioctl" ]
  [[ "$(cat "$ISTIOCTL_URL_LOG")" == */istioctl-1.31.4-osx-arm64.tar.gz ]]
}

@test "preserves the caller's EXIT trap" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]
  [ "$(command -v istioctl 2>/dev/null || true)" = "" ]
  run bash -c 'trap "echo sentinel" EXIT; source "$CORE_LIB"; _run_command() { while [ "$1" != "--" ]; do shift; done; shift; "$@"; }; _install_istioctl "$INSTALL_DIR"; trap -p EXIT'
  [ "$status" -eq 0 ]; [[ "$output" == *sentinel* ]]
}

@test "unsupported OS and architecture refuse before downloading" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]
  [[ "$TEST_TMP_ROOT" == "$BATS_TEST_TMPDIR" ]]
  for platform in FreeBSD OpenBSD; do
    export TEST_UNAME_S="$platform" TEST_UNAME_M=arm64
    run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; _install_istioctl "$INSTALL_DIR"'
    [ "$status" -eq 1 ]
    [ "$output" = "ERROR: unsupported istioctl platform: ${platform}-arm64" ]
    [ ! -s "$ISTIOCTL_URL_LOG" ]
  done
  export TEST_UNAME_S=Darwin TEST_UNAME_M=mips
  run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -eq 1 ]
  [ "$output" = "ERROR: unsupported istioctl architecture: mips" ]
  [ ! -s "$ISTIOCTL_URL_LOG" ]
}

@test "download failure reports exact error and removes temporary directory" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]; [[ "$TEST_TMP_ROOT" == "$BATS_TEST_TMPDIR" ]]
  export ISTIOCTL_CURL_FAIL=1
  run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -eq 1 ]; [ "$output" = "ERROR: failed to download istioctl 1.31.4 archive" ]
  [ ! -e "$(cat "$ISTIOCTL_TMP_LOG")" ]
}

@test "extraction failure reports exact error and removes temporary directory" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]; [[ "$TEST_TMP_ROOT" == "$BATS_TEST_TMPDIR" ]]
  export ISTIOCTL_TAR_FAIL=1
  run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; _run_command() { return 1; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -eq 1 ]; [ "$output" = "ERROR: failed to extract istioctl 1.31.4 archive" ]
  [ ! -e "$(cat "$ISTIOCTL_TMP_LOG")" ]
}

@test "plain and privileged mkdir failures report exact error and clean up" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]; [[ "$TEST_TMP_ROOT" == "$BATS_TEST_TMPDIR" ]]
  local target="$INSTALL_DIR/../new-install"
  export ISTIOCTL_MKDIR_FAIL_PATH="$target"
  run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; _run_command() { return 1; }; _install_istioctl "$INSTALL_DIR/../new-install"'
  [ "$status" -eq 1 ]; [ "$output" = "ERROR: failed to create istioctl install directory $target" ]
  [ ! -e "$(cat "$ISTIOCTL_TMP_LOG")" ]
}

@test "cp failure in writable install directory reports exact error and cleans up" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]; [[ "$TEST_TMP_ROOT" == "$BATS_TEST_TMPDIR" ]]
  export ISTIOCTL_CP_FAIL_PATH="$INSTALL_DIR/istioctl"
  run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; _run_command() { while [ "$1" != "--" ]; do shift; done; shift; "$@"; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -eq 1 ]; [ "$output" = "ERROR: failed to install istioctl into $INSTALL_DIR" ]
  [ ! -e "$(cat "$ISTIOCTL_TMP_LOG")" ]
}

@test "cp failure through prefer-sudo reports exact error and cleans up" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]; [[ "$TEST_TMP_ROOT" == "$BATS_TEST_TMPDIR" ]]
  chmod 555 "$INSTALL_DIR"
  export ISTIOCTL_CP_FAIL_PATH="$INSTALL_DIR/istioctl"
  run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; _run_command() { case "$*" in *--prefer-sudo*) while [ "$1" != "--" ]; do shift; done; shift; "$@" ;; *) return 1 ;; esac; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -eq 1 ]; [ "$output" = "ERROR: failed to install istioctl into $INSTALL_DIR" ]
  [ ! -e "$(cat "$ISTIOCTL_TMP_LOG")" ]
}

@test "post-install wrong minor reports exact error after cleanup" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]; [[ "$TEST_TMP_ROOT" == "$BATS_TEST_TMPDIR" ]]
  cat > "$BATS_TEST_TMPDIR/wrong-version" <<'EOF'
#!/bin/sh
printf '%s\n' 'client version: 1.32.0'
EOF
  chmod +x "$BATS_TEST_TMPDIR/wrong-version"
  export ISTIOCTL_WRONG_BINARY="$BATS_TEST_TMPDIR/wrong-version"
  run bash -c 'source "$CORE_LIB"; _err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }; _run_command() { if [[ "$*" == *"$INSTALL_DIR/istioctl"* ]]; then cp "$ISTIOCTL_WRONG_BINARY" "$INSTALL_DIR/istioctl"; else while [ "$1" != "--" ]; do shift; done; shift; "$@"; fi; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -eq 1 ]
  [ "$output" = "ERROR: installed istioctl 1.32.0 at $INSTALL_DIR/istioctl does not match pin 1.31.4; install a compatible release from https://github.com/istio/istio/releases, run 'brew unlink istioctl', or set ISTIOCTL_VERSION." ]
  [ ! -e "$(cat "$ISTIOCTL_TMP_LOG")" ]
}

@test "non-writable install directory uses prefer-sudo for successful copy" {
  [ "$INSTALL_DIR" = "${BATS_TEST_TMPDIR}/install" ]; [[ "$TEST_TMP_ROOT" == "$BATS_TEST_TMPDIR" ]]
  chmod 555 "$INSTALL_DIR"
  export ISTIOCTL_SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
  run bash -c 'source "$CORE_LIB"; _run_command() { case "$*" in *--prefer-sudo*) printf sudo >> "$ISTIOCTL_SUDO_LOG"; chmod 755 "$INSTALL_DIR"; while [ "$1" != "--" ]; do shift; done; shift; "$@"; local rc=$?; chmod 555 "$INSTALL_DIR"; return "$rc";; esac; while [ "$1" != "--" ]; do shift; done; shift; "$@"; }; _install_istioctl "$INSTALL_DIR"'
  [ "$status" -eq 0 ]; [ -x "$INSTALL_DIR/istioctl" ]
  [ "$(cat "$ISTIOCTL_SUDO_LOG")" = sudo ]
  [ ! -e "$(cat "$ISTIOCTL_TMP_LOG")" ]
}
