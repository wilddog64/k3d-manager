#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329

setup() {
  SYSTEM_LIB="${SYSTEM_LIB:-${BATS_TEST_DIRNAME}/../../lib/system.sh}"
  # shellcheck source=/dev/null
  source "$SYSTEM_LIB"
}

promtool_fixture() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export PROMTOOL_INSTALL_DIR="${BATS_TEST_TMPDIR}/install"
  export PROMTOOL_FIXTURE="${BATS_TEST_TMPDIR}/fixture"
  export PROMTOOL_STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  export PROMTOOL_CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  export PROMTOOL_SUDO_LOG="${BATS_TEST_TMPDIR}/sudo.log"
  export PROMTOOL_WORK_LOG="${BATS_TEST_TMPDIR}/work.log"
  export PROMTOOL_REAL_MKTEMP="$(command -v mktemp)"
  mkdir -p "$HOME" "$PROMTOOL_INSTALL_DIR" "$PROMTOOL_FIXTURE/prometheus-3.1.0.darwin-arm64" "$PROMTOOL_STUB_BIN"
  printf '#!/usr/bin/env bash\nprintf "promtool, version 3.1.0 (branch: HEAD, revision: fixture)\\n"\n' > "$PROMTOOL_FIXTURE/prometheus-3.1.0.darwin-arm64/promtool"
  chmod 0755 "$PROMTOOL_FIXTURE/prometheus-3.1.0.darwin-arm64/promtool"
  tar -czf "$PROMTOOL_FIXTURE/fixture.tar.gz" -C "$PROMTOOL_FIXTURE" prometheus-3.1.0.darwin-arm64
  export PROMTOOL_FIXTURE_SHA="$(shasum -a 256 "$PROMTOOL_FIXTURE/fixture.tar.gz" | awk '{print $1}')"
  cat > "$PROMTOOL_STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then out="$2"; shift 2; else printf '%s\n' "$1" >> "$PROMTOOL_CURL_LOG"; shift; fi
done
cp "$PROMTOOL_FIXTURE/fixture.tar.gz" "$out"
EOF
  cat > "$PROMTOOL_STUB_BIN/uname" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -s ]]; then printf '%s\n' "${FIXTURE_UNAME_S:-Darwin}"; else printf '%s\n' "${FIXTURE_UNAME_M:-arm64}"; fi
EOF
  cat > "$PROMTOOL_STUB_BIN/mktemp" <<'EOF'
#!/usr/bin/env bash
path="$("$PROMTOOL_REAL_MKTEMP" "$@")" || exit $?
printf '%s\n' "$path" >> "$PROMTOOL_WORK_LOG"
printf '%s\n' "$path"
EOF
  cat > "$PROMTOOL_STUB_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PROMTOOL_SUDO_LOG"
exit 99
EOF
  chmod 0755 "$PROMTOOL_STUB_BIN/curl" "$PROMTOOL_STUB_BIN/uname" "$PROMTOOL_STUB_BIN/mktemp" "$PROMTOOL_STUB_BIN/sudo"
  PATH="$PROMTOOL_STUB_BIN:$PATH"
  export PATH
  [ "$(command -v curl)" = "$PROMTOOL_STUB_BIN/curl" ]
  [[ "$PROMTOOL_INSTALL_DIR" == "$BATS_TEST_TMPDIR"/* ]]
  _promtool_pinned_sha256() { printf '%s\n' "$PROMTOOL_FIXTURE_SHA"; }
}

@test "_promtool_pinned_sha256 returns the four pinned checksums" {
  [ "$(_promtool_pinned_sha256 3.1.0 darwin amd64)" = de958826f9ca20003b30c48fa3f2fcfa67b2a3aebcabd6230e90bb94f92d86e8 ]
  [ "$(_promtool_pinned_sha256 3.1.0 darwin arm64)" = 8ebe1d60d8864ae3e10a359c3b543563e972505e5ef6fe1d00586d86a7e813fc ]
  [ "$(_promtool_pinned_sha256 3.1.0 linux amd64)" = 9a9d1e115d1745826b13aec3f1409780b9fcf1d4206746cb4faee46ca5add70c ]
  [ "$(_promtool_pinned_sha256 3.1.0 linux arm64)" = c12b9e368006873df0c8865771af0434a3edfc8c8eaeea62b73d3974bff7f2a1 ]
  run _promtool_pinned_sha256 9.9.9 linux amd64
  [ "$status" -eq 1 ]
  run _promtool_pinned_sha256 3.1.0 freebsd amd64
  [ "$status" -eq 1 ]
}

@test "_install_promtool installs verified archive and skips matching version" {
  promtool_fixture
  run _install_promtool
  [ "$status" -eq 0 ]
  [ -x "$PROMTOOL_INSTALL_DIR/promtool" ]
  [[ "$("$PROMTOOL_INSTALL_DIR/promtool" --version)" == 'promtool, version 3.1.0 '* ]]
  cp "$PROMTOOL_INSTALL_DIR/promtool" "$BATS_TEST_TMPDIR/original"
  run _install_promtool
  [ "$status" -eq 0 ]
  cmp -s "$BATS_TEST_TMPDIR/original" "$PROMTOOL_INSTALL_DIR/promtool"
  [ "$(grep -c 'prometheus-3.1.0.darwin-arm64.tar.gz' "$PROMTOOL_CURL_LOG")" -eq 1 ]
  [ ! -s "$PROMTOOL_SUDO_LOG" ]
  while IFS= read -r work_path; do [ ! -e "$work_path" ]; done < "$PROMTOOL_WORK_LOG"
}

@test "_install_promtool maps supported platforms and replaces old version" {
  promtool_fixture
  for mapping in 'Darwin arm64 darwin-arm64' 'Darwin x86_64 darwin-amd64' 'Linux x86_64 linux-amd64' 'Linux aarch64 linux-arm64'; do
    set -- $mapping
    export FIXTURE_UNAME_S="$1" FIXTURE_UNAME_M="$2"
    mkdir -p "$PROMTOOL_FIXTURE/prometheus-3.1.0.$3"
    if [[ "$3" != darwin-arm64 ]]; then cp "$PROMTOOL_FIXTURE/prometheus-3.1.0.darwin-arm64/promtool" "$PROMTOOL_FIXTURE/prometheus-3.1.0.$3/promtool"; fi
    tar -czf "$PROMTOOL_FIXTURE/fixture.tar.gz" -C "$PROMTOOL_FIXTURE" "prometheus-3.1.0.$3"
    export PROMTOOL_FIXTURE_SHA="$(shasum -a 256 "$PROMTOOL_FIXTURE/fixture.tar.gz" | awk '{print $1}')"
    platform_asset="$3"
    PROMTOOL_INSTALL_DIR="$BATS_TEST_TMPDIR/install-$1-$2"; export PROMTOOL_INSTALL_DIR
    mkdir -p "$PROMTOOL_INSTALL_DIR"
    if [[ ! -e "$PROMTOOL_INSTALL_DIR/promtool" ]]; then
      printf '#!/bin/sh\necho old\n' > "$PROMTOOL_INSTALL_DIR/promtool"
      chmod 0755 "$PROMTOOL_INSTALL_DIR/promtool"
    fi
    run _install_promtool
    [ "$status" -eq 0 ]
    [[ "$("$PROMTOOL_INSTALL_DIR/promtool" --version)" == 'promtool, version 3.1.0 '* ]]
    grep -F "prometheus-3.1.0.$platform_asset.tar.gz" "$PROMTOOL_CURL_LOG"
  done
  [ ! -s "$PROMTOOL_SUDO_LOG" ]
}

@test "_install_promtool refuses checksum and platform failures without leftovers" {
  promtool_fixture
  _promtool_pinned_sha256() { printf '%s\n' wrong; }
  run _install_promtool
  [ "$status" -eq 1 ]
  [ ! -e "$PROMTOOL_INSTALL_DIR/promtool" ]
  [ -z "$(find "$PROMTOOL_INSTALL_DIR" -name promtool -print)" ]
  [ -z "$(find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'tmp.*' -print)" ]
  while IFS= read -r work_path; do [ ! -e "$work_path" ]; done < "$PROMTOOL_WORK_LOG"
  : > "$PROMTOOL_CURL_LOG"
  _promtool_pinned_sha256() { return 1; }
  run env PROMTOOL_VERSION=9.9.9 SYSTEM_LIB="$SYSTEM_LIB" HOME="$HOME" PROMTOOL_INSTALL_DIR="$PROMTOOL_INSTALL_DIR" PATH="$PATH" bash -c 'set -e; source "$SYSTEM_LIB"; if _install_promtool; then exit 77; else echo caller-survived; fi'
  [ "$status" -eq 0 ]
  [[ "$output" == *caller-survived* ]]
  [ ! -s "$PROMTOOL_CURL_LOG" ]
  export FIXTURE_UNAME_S=Plan9
  run _install_promtool
  [ "$status" -eq 1 ]
  [ ! -s "$PROMTOOL_CURL_LOG" ]
  export FIXTURE_UNAME_S=Linux FIXTURE_UNAME_M=sparc
  run _install_promtool
  [ "$status" -eq 1 ]
  [ ! -s "$PROMTOOL_CURL_LOG" ]
  [ ! -s "$PROMTOOL_SUDO_LOG" ]
}

foundation_vcluster_fixture() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export FIXTURE="${BATS_TEST_TMPDIR}/fixture"
  export VCLUSTER_STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  mkdir -p "${FIXTURE}" "${VCLUSTER_STUB_BIN}"
  printf '#!/usr/bin/env bash\nprintf "vcluster version %s\\n"\n' "${VCLUSTER_FIXTURE_VERSION:-0.20.0}" > "${FIXTURE}/asset"
  chmod 0755 "${FIXTURE}/asset"
  shasum -a 256 "${FIXTURE}/asset" | awk '{print $1 "  vcluster-darwin-arm64"}' > "${FIXTURE}/checksums.txt"
  cat > "${VCLUSTER_STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -e
out=""
previous=""
endopts=0
for arg in "$@"; do
  if [[ "${endopts}" -eq 0 && "${arg}" == "--" ]]; then endopts=1; previous=""; continue; fi
  if [[ "${endopts}" -eq 0 && "${previous}" == "-o" ]]; then out="${arg}"; fi
  previous="${arg}"
done
printf '%s\n' "$*" >> "${CURL_LOG}"
if [[ "$*" == *checksums.txt* ]]; then cp -- "${FIXTURE}/checksums.txt" "${out}"; else cp -- "${FIXTURE}/asset" "${out}"; fi
EOF
  cat > "${VCLUSTER_STUB_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-s" ]]; then printf '%s\n' "${UNAME_S:-Darwin}"; else printf '%s\n' "${UNAME_M:-arm64}"; fi
EOF
  chmod 0755 "${VCLUSTER_STUB_BIN}/curl" "${VCLUSTER_STUB_BIN}/uname"
  PATH="${VCLUSTER_STUB_BIN}:${PATH}"
  export PATH
}

foundation_vcluster_managed_binary() {
  printf '%s/lib-foundation/vcluster/0.20.0/vcluster\n' "${XDG_DATA_HOME}"
}

bats_require_minimum_version 1.5.0

secret_store_fixture() {
  export SECRET_STUB_DIR="${BATS_TEST_TMPDIR}/secret-bin"
  export ARGV_LOG="${BATS_TEST_TMPDIR}/security.argv"
  export STDIN_LOG="${BATS_TEST_TMPDIR}/security.stdin"
  export STORE_FILE="${BATS_TEST_TMPDIR}/security.store"
  mkdir -p "${SECRET_STUB_DIR}"
  : > "${ARGV_LOG}"
  : > "${STDIN_LOG}"
  : > "${STORE_FILE}"
  cat > "${SECRET_STUB_DIR}/security" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ARGV_LOG}"
input=""
if [[ "${1:-}" == -i ]]; then
  input="$(cat)"
  printf '%s\n' "${input}" >> "${STDIN_LOG}"
fi
if [[ "${1:-}" == delete-generic-password ]]; then
  : > "${STORE_FILE}"
  exit 0
fi
if [[ "${1:-}" == find-generic-password ]]; then
  if [[ -s "${STORE_FILE}" ]]; then
    cat "${STORE_FILE}"
    exit 0
  fi
  exit 44
fi
if [[ "${1:-}" == -i ]]; then
  [[ "${FAIL_SECURITY:-0}" == 1 ]] && exit 36
  hex="${input#* -X }"
  hex="${hex#\"}"
  hex="${hex%\"}"
  printf '%s' "${hex}" | xxd -r -p > "${STORE_FILE}"
  exit 0
fi
exit 45
EOF
  chmod 0755 "${SECRET_STUB_DIR}/security"
  PATH="${SECRET_STUB_DIR}:${PATH}"
  export PATH
  _is_mac() { return 0; }
  export -f _is_mac
}

@test "_secret_store_data: sends the value as hex on security stdin, never argv" {
  secret_store_fixture
  run _secret_store_data svc key SENTINEL-abc123
  [ "$status" -eq 0 ]
  run grep -Fq 'SENTINEL-abc123' "${ARGV_LOG}"
  [ "$status" -ne 0 ]
  run grep -Fq '53454e54494e454c2d616263313233' "${ARGV_LOG}"
  [ "$status" -ne 0 ]
  grep -Fq '53454e54494e454c2d616263313233' "${STDIN_LOG}"
  run _secret_load_data svc key
  [ "$status" -eq 0 ]
  [ "$output" = 'SENTINEL-abc123' ]
}

@test "_secret_store_data: preserves spaces, quotes, backslash, and percent" {
  secret_store_fixture
  value='space "double" '\''single'\'' \\ percent%'
  run _secret_store_data svc key "${value}"
  [ "$status" -eq 0 ]
  run _secret_load_data svc key
  [ "$status" -eq 0 ]
  [ "$output" = "${value}" ]
}

@test "_secret_store_data: reports a failed security write" {
  secret_store_fixture
  export FAIL_SECURITY=1
  run _secret_store_data svc key value
  [ "$status" -ne 0 ]
}

@test "_secret_store_data: failed update keeps the existing item and does not delete" {
  secret_store_fixture
  printf '%s' old-value > "${STORE_FILE}"
  export FAIL_SECURITY=1
  run _secret_store_data svc key new-value
  [ "$status" -ne 0 ]
  run _secret_load_data svc key
  [ "$status" -eq 0 ]
  [ "$output" = old-value ]
  run grep -Fq delete-generic-password "${ARGV_LOG}"
  [ "$status" -ne 0 ]
  run grep -Fq delete-generic-password "${STDIN_LOG}"
  [ "$status" -ne 0 ]
}

@test "_secret_store_data: rejects whitespace in service without calling security" {
  secret_store_fixture
  run _secret_store_data 'svc with-space' key value
  [ "$status" -eq 1 ]
  [ ! -s "${ARGV_LOG}" ]
  [ ! -s "${STDIN_LOG}" ]
}

@test "_secret_store_data: rejects quotes and a backslash in service or key" {
  secret_store_fixture
  local name
  for name in 'a"b' "a'b" 'a\b'; do
    run _secret_store_data svc "${name}" value
    [ "$status" -eq 1 ]
    run _secret_store_data "${name}" key value
    [ "$status" -eq 1 ]
  done
  [ ! -s "${ARGV_LOG}" ]
  [ ! -s "${STDIN_LOG}" ]
}

@test "_secret_store_data: accepts ordinary names containing x, 2 and 7" {
  secret_store_fixture
  run _secret_store_data k3dm-vault-x27 'k3d-cluster:shard2' value
  [ "$status" -eq 0 ]
  grep -Fq 'add-generic-password -U -s k3dm-vault-x27 -a k3d-cluster:shard2 -X ' "${STDIN_LOG}"
}

@test "_secret_store_data: stores an empty value with an empty hex argument" {
  secret_store_fixture
  run _secret_store_data svc key ""
  [ "$status" -eq 0 ]
  grep -Fq 'add-generic-password -U -s svc -a key -X ""' "${STDIN_LOG}"
  [ -f "${STORE_FILE}" ]
}

@test "_dry_run_active true only when DRY_RUN=1" {
  run bash -c "source \"$SYSTEM_LIB\"; DRY_RUN=1 _dry_run_active"
  [ "$status" -eq 0 ]
  run bash -c "source \"$SYSTEM_LIB\"; DRY_RUN=0 _dry_run_active"
  [ "$status" -ne 0 ]
  run bash -c "source \"$SYSTEM_LIB\"; unset DRY_RUN; _dry_run_active"
  [ "$status" -ne 0 ]
}

@test "_dry_guard in DRY_RUN logs intent and does NOT execute" {
  sentinel="$(mktemp)"
  rm -f "${sentinel}"
  run bash -c "source \"$SYSTEM_LIB\"; DRY_RUN=1 _dry_guard 'create marker' touch '${sentinel}'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN: would create marker"* ]]
  [ ! -e "${sentinel}" ]
}

@test "_dry_guard outside DRY_RUN executes and preserves exit status" {
  sentinel="$(mktemp)"
  rm -f "${sentinel}"
  run bash -c "source \"$SYSTEM_LIB\"; DRY_RUN=0 _dry_guard 'create marker' touch '${sentinel}'"
  [ "$status" -eq 0 ]
  [ -e "${sentinel}" ]
  rm -f "${sentinel}"
  run bash -c "source \"$SYSTEM_LIB\"; DRY_RUN=0 _dry_guard \"fail\" false"
  [ "$status" -eq 1 ]
}

@test "_run_command_resolve_sudo: no sudo flags → plain runner" {
  _RCRS_RUNNER=()
  _run_command_resolve_sudo "echo" 0 0 0
  [ "${_RCRS_RUNNER[0]}" = "echo" ]
  [ "${#_RCRS_RUNNER[@]}" -eq 1 ]
  unset _RCRS_RUNNER
}

@test "_run_command_resolve_sudo: require_sudo unavailable → returns 127" {
  function sudo() { return 1; }
  export -f sudo
  _RCRS_RUNNER=()
  run -127 _run_command_resolve_sudo "echo" 0 1 0
  unset -f sudo
  unset _RCRS_RUNNER
}

@test "_run_command_resolve_sudo: probe succeeds as user → plain runner" {
  _RCRS_RUNNER=()
  _run_command_resolve_sudo "true" 1 0 0 "--version"
  [ "${_RCRS_RUNNER[0]}" = "true" ]
  unset _RCRS_RUNNER
}

@test "_run_command_resolve_sudo: sudo runner uses the system binary, not a PATH shadow" {
  shadow_dir="${BATS_TEST_TMPDIR}/shadow"
  mkdir -p "${shadow_dir}"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "${shadow_dir}/install"
  chmod +x "${shadow_dir}/install"
  saved_path="$PATH"
  PATH="${shadow_dir}:${PATH}"
  _run_command_resolve_sudo install 1 0 1 </dev/null
  [ "${_RCRS_RUNNER[0]}" = "sudo" ]
  [ "${_RCRS_RUNNER[1]}" = "-n" ]
  [ "${_RCRS_RUNNER[2]}" = "/usr/bin/install" ]
  [ "${#_RCRS_RUNNER[@]}" -eq 3 ]
  PATH="$saved_path"
  unset _RCRS_RUNNER
}

@test "_run_command_resolve_sudo: interactive sudo without a TTY adds -n" {
  _run_command_resolve_sudo echo 1 0 1 </dev/null
  [ "${_RCRS_RUNNER[0]}" = "sudo" ]
  [ "${_RCRS_RUNNER[1]}" = "-n" ]
  unset _RCRS_RUNNER
}

@test "_run_command_resolve_sudo: plain runner keeps the bare name" {
  _run_command_resolve_sudo install 0 0 0
  [ "${_RCRS_RUNNER[0]}" = "install" ]
  [ "${#_RCRS_RUNNER[@]}" -eq 1 ]
  unset _RCRS_RUNNER
}

@test "_run_command_resolve_sudo: absolute program path is left unchanged" {
  _run_command_resolve_sudo /opt/custom/tool 1 0 1 </dev/null
  [ "${_RCRS_RUNNER[${#_RCRS_RUNNER[@]}-1]}" = "/opt/custom/tool" ]
  unset _RCRS_RUNNER
}

@test "_run_command: missing program → exits 127" {
  run -127 _run_command --soft -- __nonexistent_prog_xyz__
}

@test "_run_command: succeeds for simple command" {
  run _run_command -- echo hello
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "_run_command: --quiet suppresses error output on missing program" {
  run -127 _run_command --quiet --soft -- __nonexistent_prog_xyz__
  [ -z "$output" ]
}

@test "_run_command: --interactive-sudo flag is accepted without error" {
  function sudo() { while [[ $# -gt 0 && "$1" == -* ]]; do shift; done; "$@"; }
  export -f sudo
  run _run_command --interactive-sudo --soft -- echo hi
  [ "$status" -eq 0 ]
  [ "$output" = "hi" ]
  unset -f sudo
}

@test "_run_command: --prefer-sudo flag is accepted without error" {
  function sudo() { while [[ $# -gt 0 && "$1" == -* ]]; do shift; done; "$@"; }
  export -f sudo
  run _run_command --prefer-sudo --soft -- echo hi
  [ "$status" -eq 0 ]
  [ "$output" = "hi" ]
  unset -f sudo
}

@test "_run_command_handle_failure: soft mode returns rc without exiting" {
  run _run_command_handle_failure "myprog" 42 0 1 myprog arg1
  [ "$status" -eq 42 ]
}

@test "_run_command_handle_failure: quiet=1 suppresses output" {
  run _run_command_handle_failure "myprog" 1 1 1 myprog arg1
  [ -z "$output" ]
  [ "$status" -eq 1 ]
}

@test "_node_install_via_redhat: returns 1 when no redhat package manager present" {
  _command_exist() { return 1; }
  export -f _command_exist

  run _node_install_via_redhat
  [ "$status" -eq 1 ]
  unset -f _command_exist
}

@test "_ensure_antigravity_ide: returns 0 when agy exists" {
  _command_exist() { [[ "$1" == agy ]]; }
  export -f _command_exist

  run _ensure_antigravity_ide
  [ "$status" -eq 0 ]
  unset -f _command_exist
}

@test "_ensure_antigravity_ide: returns 0 when antigravity exists" {
  _command_exist() { [[ "$1" == antigravity ]]; }
  export -f _command_exist

  run _ensure_antigravity_ide
  [ "$status" -eq 0 ]
  unset -f _command_exist
}

@test "_ensure_antigravity_ide: installs via brew on macOS" {
  installed=0
  _command_exist() {
    case "$1" in
      antigravity) [[ "$installed" -eq 1 ]] ;;
      brew) return 0 ;;
      *) return 1 ;;
    esac
  }
  _is_mac() { return 0; }
  _run_command() {
    if [[ "$*" == *"brew install --cask antigravity"* ]]; then
      installed=1
    fi
    return 0
  }
  export -f _command_exist _is_mac _run_command

  run _ensure_antigravity_ide
  [ "$status" -eq 0 ]
  unset -f _command_exist _is_mac _run_command
}

@test "_ensure_antigravity_ide: installs via apt-get on Debian" {
  installed=0
  _command_exist() {
    case "$1" in
      antigravity) [[ "$installed" -eq 1 ]] ;;
      apt-get) return 0 ;;
      *) return 1 ;;
    esac
  }
  _is_mac() { return 1; }
  _is_debian_family() { return 0; }
  _is_redhat_family() { return 1; }
  _sudo_available() { return 0; }
  _run_command() {
    if [[ "$*" == *"apt-get install"*"antigravity"* ]]; then
      installed=1
    fi
    return 0
  }
  export -f _command_exist _is_mac _is_debian_family _is_redhat_family _sudo_available _run_command

  run _ensure_antigravity_ide
  [ "$status" -eq 0 ]
  unset -f _command_exist _is_mac _is_debian_family _is_redhat_family _sudo_available _run_command
}

@test "_ensure_agy_cli: returns 0 when agy exists" {
  _command_exist() { [[ "$1" == agy ]]; }
  export -f _command_exist

  run _ensure_agy_cli
  [ "$status" -eq 0 ]
  unset -f _command_exist
}

@test "_ensure_agy_cli: errors when curl is missing" {
  export HOME="${BATS_TEST_TMPDIR}"
  _command_exist() { return 1; }
  _err() { echo "$*"; exit 1; }
  export -f _command_exist _err

  run _ensure_agy_cli
  [ "$status" -ne 0 ]
  [[ "$output" == *"curl is required"* ]]

  unset -f _command_exist _err
}

@test "_ensure_agy_cli: installs via curl | bash into ~/.local/bin" {
  export HOME="${BATS_TEST_TMPDIR}"
  installed_bin="${HOME}/.local/bin/agy"
  stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_dir}"
  cat > "${stub_dir}/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'SH'
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/agy" <<'AGY'
#!/usr/bin/env bash
printf 'agy CLI\n'
AGY
chmod +x "$HOME/.local/bin/agy"
SH
EOF
  chmod +x "${stub_dir}/curl"

  _command_exist() {
    case "$1" in
      curl) return 0 ;;
      agy) [[ -x "${installed_bin}" ]] ;;
      *) return 1 ;;
    esac
  }
  export -f _command_exist
  PATH="${stub_dir}:$PATH"

  run _ensure_agy_cli
  [ "$status" -eq 0 ]
  [ -x "${installed_bin}" ]

  unset -f _command_exist
}

@test "_ensure_antigravity_mcp_playwright: no-op when playwright entry already present" {
  config_file="$(mktemp -t ag-mcp-test.XXXXXX)"
  printf '{"mcpServers":{"playwright":{"command":"npx","args":["-y","@playwright/mcp@0.0.26"]}}}\n' > "$config_file"

  _antigravity_mcp_config_path() { printf '%s\n' "$config_file"; }
  _command_exist() { [[ "$1" == jq ]]; }
  export -f _antigravity_mcp_config_path _command_exist

  run _ensure_antigravity_mcp_playwright
  [ "$status" -eq 0 ]

  rm -f "$config_file"
  unset -f _antigravity_mcp_config_path _command_exist
}

@test "_ensure_antigravity_mcp_playwright: injects playwright entry into empty config" {
  config_dir="$(mktemp -d -t ag-mcp-dir.XXXXXX)"
  config_file="${config_dir}/mcp_config.json"

  _antigravity_mcp_config_path() { printf '%s\n' "$config_file"; }
  _command_exist() { [[ "$1" == jq ]]; }
  export -f _antigravity_mcp_config_path _command_exist

  run _ensure_antigravity_mcp_playwright
  [ "$status" -eq 0 ]
  grep -q '"playwright"' "$config_file"

  rm -rf "$config_dir"
  unset -f _antigravity_mcp_config_path _command_exist
}

@test "_antigravity_browser_ready: returns 0 when port 9222 responds" {
  _command_exist() { [[ "$1" == curl ]]; }
  _run_command() { return 0; }
  export -f _command_exist _run_command

  run _antigravity_browser_ready 4
  [ "$status" -eq 0 ]
  unset -f _command_exist _run_command
}

@test "_antigravity_browser_ready: fails fast when curl missing" {
  _command_exist() { return 1; }
  _err() { echo "$*"; exit 1; }
  export -f _command_exist _err

  run _antigravity_browser_ready 5
  [ "$status" -ne 0 ]
  [[ "$output" == *"curl is required"* ]]
  unset -f _command_exist _err
}

@test "_antigravity_browser_ready: errors when port never responds within timeout" {
  _command_exist() { [[ "$1" == curl ]]; }
  _run_command() { return 1; }
  _err() { echo "ERROR: $*" >&2; return 1; }
  export -f _command_exist _run_command _err

  run _antigravity_browser_ready 2
  [ "$status" -ne 0 ]
  unset -f _command_exist _run_command _err
}

@test "foundation_ensure_vcluster_cli: reuses exact verified binary without download" {
  foundation_vcluster_fixture
  managed="$(foundation_vcluster_managed_binary)"
  mkdir -p "${managed%/*}"
  cp -- "${FIXTURE}/asset" "${managed}"
  chmod 0755 "${managed}"
  run foundation_ensure_vcluster_cli 0.20.0
  [ "$status" -eq 0 ]
  [ "$output" = "${managed}" ]
  [ ! -s "${CURL_LOG}" ]
}

@test "foundation_ensure_vcluster_cli: replaces mismatched binary through verified download" {
  foundation_vcluster_fixture
  managed="$(foundation_vcluster_managed_binary)"
  mkdir -p "${managed%/*}"
  printf '#!/usr/bin/env bash\nprintf "vcluster version 0.19.0\\n"\n' > "${managed}"
  chmod 0755 "${managed}"
  run foundation_ensure_vcluster_cli 0.20.0
  [ "$status" -eq 0 ]
  [ "$output" = "${managed}" ]
  [[ "$("${managed}" --version)" == *"0.20.0"* ]]
  [ "$(wc -l < "${CURL_LOG}")" -eq 2 ]
}

@test "foundation_ensure_vcluster_cli: malformed and unsupported inputs do not write" {
  foundation_vcluster_fixture
  run foundation_ensure_vcluster_cli v0.20.0
  [ "$status" -ne 0 ]
  [ ! -e "${XDG_DATA_HOME}/lib-foundation" ]
  export UNAME_S="FreeBSD"
  run foundation_ensure_vcluster_cli 0.20.0
  [ "$status" -ne 0 ]
  [ ! -e "${XDG_DATA_HOME}/lib-foundation" ]
}

@test "foundation_ensure_vcluster_cli: checksum mismatch preserves prior binary" {
  foundation_vcluster_fixture
  managed="$(foundation_vcluster_managed_binary)"
  mkdir -p "${managed%/*}"
  printf '#!/usr/bin/env bash\nprintf "vcluster version 0.19.0\\n"\n' > "${managed}"
  chmod 0755 "${managed}"
  printf '%064d  vcluster-darwin-arm64\n' 0 > "${FIXTURE}/checksums.txt"
  run foundation_ensure_vcluster_cli 0.20.0
  [ "$status" -ne 0 ]
  [[ "$("${managed}" --version)" == *"0.19.0"* ]]
  [ -z "$(find "${managed%/*}" -name '.vcluster.*' 2>/dev/null)" ]
}

@test "foundation_ensure_vcluster_cli: failed download preserves prior binary" {
  foundation_vcluster_fixture
  managed="$(foundation_vcluster_managed_binary)"
  mkdir -p "${managed%/*}"
  printf '#!/usr/bin/env bash\nprintf "vcluster version 0.19.0\\n"\n' > "${managed}"
  chmod 0755 "${managed}"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 22' > "${VCLUSTER_STUB_BIN}/curl"
  chmod 0755 "${VCLUSTER_STUB_BIN}/curl"
  run foundation_ensure_vcluster_cli 0.20.0
  [ "$status" -ne 0 ]
  [[ "$("${managed}" --version)" == *"0.19.0"* ]]
}

@test "foundation_ensure_vcluster_cli: holds the lock through the download under functrace" {
  foundation_vcluster_fixture
  [[ "$-" == *T* ]]
  mv "${VCLUSTER_STUB_BIN}/curl" "${VCLUSTER_STUB_BIN}/curl.real"
  cat > "${VCLUSTER_STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
if [[ -d "${XDG_DATA_HOME}/lib-foundation/vcluster/0.20.0.lock" ]]; then echo held >> "${BATS_TEST_TMPDIR}/lock.log"; else echo dropped >> "${BATS_TEST_TMPDIR}/lock.log"; fi
exec "${VCLUSTER_STUB_BIN}/curl.real" "$@"
EOF
  chmod 0755 "${VCLUSTER_STUB_BIN}/curl"
  foundation_ensure_vcluster_cli 0.20.0 > /dev/null
  [ "$(sort -u "${BATS_TEST_TMPDIR}/lock.log")" = "held" ]
  [ ! -e "${XDG_DATA_HOME}/lib-foundation/vcluster/0.20.0.lock" ]
}

@test "foundation_ensure_vcluster_cli: concurrent callers leave one binary and no lock" {
  foundation_vcluster_fixture
  output_one="${BATS_TEST_TMPDIR}/one.out"; output_two="${BATS_TEST_TMPDIR}/two.out"
  (source "${SYSTEM_LIB}"; foundation_ensure_vcluster_cli 0.20.0 > "${output_one}") & first=$!
  (source "${SYSTEM_LIB}"; foundation_ensure_vcluster_cli 0.20.0 > "${output_two}") & second=$!
  wait "${first}"; first_status=$?
  wait "${second}"; second_status=$?
  [ "${first_status}" -eq 0 ]
  [ "${second_status}" -eq 0 ]
  [ -x "$(foundation_vcluster_managed_binary)" ]
  [ ! -e "${XDG_DATA_HOME}/lib-foundation/vcluster/0.20.0.lock" ]
  [ -z "$(find "${XDG_DATA_HOME}" -name '.vcluster.*' -o -name 'foundation-vcluster.*' 2>/dev/null)" ]
}

@test "foundation_ensure_vcluster_cli: never invokes package managers" {
  foundation_vcluster_fixture
  for manager in brew apt apt-get dnf npm pip; do
    printf '#!/usr/bin/env bash\nprintf "%s\\n" invoked >> "${MANAGER_LOG}"\nexit 99\n' "${manager}" > "${VCLUSTER_STUB_BIN}/${manager}"
    chmod 0755 "${VCLUSTER_STUB_BIN}/${manager}"
  done
  export MANAGER_LOG="${BATS_TEST_TMPDIR}/manager.log"
  run foundation_ensure_vcluster_cli 0.20.0
  [ "$status" -eq 0 ]
  [ ! -e "${MANAGER_LOG}" ]
}

macmon_fixture() {
  export MACMON_BIN="${BATS_TEST_TMPDIR}/macmon-bin"
  export MACMON_LOG="${BATS_TEST_TMPDIR}/macmon.log"
  mkdir -p "${MACMON_BIN}"
  : > "${MACMON_LOG}"
  cat > "${MACMON_BIN}/uname" <<'STUB'
#!/bin/bash
# uname -m captured on m4-air, 2026-11-01: arm64
printf '%s\n' "${MACMON_ARCH:-arm64}"
STUB
  cat > "${MACMON_BIN}/brew" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${MACMON_LOG}"
exit "${MACMON_BREW_STATUS:-0}"
STUB
  cat > "${MACMON_BIN}/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "${MACMON_LOG}"
exit 1
STUB
  chmod +x "${MACMON_BIN}/uname" "${MACMON_BIN}/brew" "${MACMON_BIN}/sudo"
  export PATH="${MACMON_BIN}:/usr/bin:/bin"
  [ "$(command -v brew)" = "${MACMON_BIN}/brew" ]
  _is_mac() { return 0; }
}

@test "_install_macmon installs on Apple Silicon" {
  macmon_fixture
  run _install_macmon
  [ "$status" -eq 0 ]
  [ "$(cat "${MACMON_LOG}")" = "install macmon" ]
  [[ "$output" == *"macmon installed"* ]]
}

@test "_install_macmon skips an existing binary" {
  macmon_fixture
  printf '#!/bin/bash\nexit 0\n' > "${MACMON_BIN}/macmon"
  chmod +x "${MACMON_BIN}/macmon"
  run _install_macmon
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "${MACMON_LOG}" ]
}

@test "_install_macmon returns install failure" {
  macmon_fixture
  export MACMON_BREW_STATUS=1
  run _install_macmon
  [ "$status" -ne 0 ]
  [ "$(cat "${MACMON_LOG}")" = "install macmon" ]
}

@test "_install_macmon skips Linux" {
  macmon_fixture
  _is_mac() { return 1; }
  run _install_macmon
  [ "$status" -eq 0 ]
  [ ! -s "${MACMON_LOG}" ]
}

@test "_install_macmon skips Intel Macs" {
  macmon_fixture
  export MACMON_ARCH=x86_64
  run _install_macmon
  [ "$status" -eq 0 ]
  [ ! -s "${MACMON_LOG}" ]
}

@test "_install_macmon requires Homebrew without sudo" {
  macmon_fixture
  rm "${MACMON_BIN}/brew"
  run _install_macmon
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew is required to install macmon"* ]]
  [ ! -s "${MACMON_LOG}" ]
}

vm_cask_fixture() {
  export VM_CASK_BIN="${BATS_TEST_TMPDIR}/vm-cask-bin"
  export VM_CASK_LOG="${BATS_TEST_TMPDIR}/vm-cask.log"
  mkdir -p "${VM_CASK_BIN}"
  : > "${VM_CASK_LOG}"
  cat > "${VM_CASK_BIN}/brew" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${VM_CASK_LOG}"
exit "${VM_CASK_BREW_STATUS:-0}"
STUB
  cat > "${VM_CASK_BIN}/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "${VM_CASK_LOG}"
exit 1
STUB
  for binary in VBoxManage vagrant; do
    cat > "${VM_CASK_BIN}/${binary}" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  done
  chmod +x "${VM_CASK_BIN}/brew" "${VM_CASK_BIN}/sudo" "${VM_CASK_BIN}/VBoxManage" "${VM_CASK_BIN}/vagrant"
  export PATH="${VM_CASK_BIN}:/usr/bin:/bin"
  [ "$(command -v brew)" = "${VM_CASK_BIN}/brew" ]
  _is_mac() { return 0; }
}

@test "_install_virtualbox installs its cask when VBoxManage is absent" {
  vm_cask_fixture
  rm "${VM_CASK_BIN}/VBoxManage"
  run _install_virtualbox
  [ "${status}" -eq 0 ]
  [ "$(cat "${VM_CASK_LOG}")" = "install --cask virtualbox" ]
  [[ "${output}" == *"VirtualBox installed"* ]]
}

@test "_install_vagrant installs its cask when vagrant is absent" {
  vm_cask_fixture
  rm "${VM_CASK_BIN}/vagrant"
  run _install_vagrant
  [ "${status}" -eq 0 ]
  [ "$(cat "${VM_CASK_LOG}")" = "install --cask vagrant" ]
  [[ "${output}" == *"Vagrant installed"* ]]
}

@test "VM cask installers skip existing binaries without calling brew" {
  vm_cask_fixture
  run _install_virtualbox
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  run _install_vagrant
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ ! -s "${VM_CASK_LOG}" ]
}

@test "VM cask installers install independently when the other binary exists" {
  vm_cask_fixture
  rm "${VM_CASK_BIN}/VBoxManage"
  run _install_virtualbox
  [ "${status}" -eq 0 ]
  [ "$(cat "${VM_CASK_LOG}")" = "install --cask virtualbox" ]
  : > "${VM_CASK_LOG}"
  rm "${VM_CASK_BIN}/vagrant"
  run _install_vagrant
  [ "${status}" -eq 0 ]
  [ "$(cat "${VM_CASK_LOG}")" = "install --cask vagrant" ]
}

@test "VM cask installer failure returns non-zero and caller continues" {
  vm_cask_fixture
  rm "${VM_CASK_BIN}/VBoxManage"
  export VM_CASK_BREW_STATUS=17
  if _install_virtualbox; then status=0; else status=$?; fi
  [ "${status}" -eq 17 ]
  [ "$(cat "${VM_CASK_LOG}")" = "install --cask virtualbox" ]
}

@test "VM cask installers reject non-macOS without calling brew" {
  vm_cask_fixture
  _is_mac() { return 1; }
  run _install_virtualbox
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"VirtualBox installation is supported only on macOS"* ]]
  run _install_vagrant
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Vagrant installation is supported only on macOS"* ]]
  [ ! -s "${VM_CASK_LOG}" ]
}

@test "VM cask installers require Homebrew without calling sudo" {
  vm_cask_fixture
  rm "${VM_CASK_BIN}/VBoxManage" "${VM_CASK_BIN}/vagrant" "${VM_CASK_BIN}/brew"
  run _install_virtualbox
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Homebrew is required to install VirtualBox"* ]]
  run _install_vagrant
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Homebrew is required to install Vagrant"* ]]
  [ ! -s "${VM_CASK_LOG}" ]
}
