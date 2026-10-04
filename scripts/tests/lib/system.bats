#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329

setup() {
  SYSTEM_LIB="${BATS_TEST_DIRNAME}/../../lib/system.sh"
  # shellcheck source=/dev/null
  source "$SYSTEM_LIB"
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
  [ ! -e "${managed%/*}/.vcluster.$$" ]
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
