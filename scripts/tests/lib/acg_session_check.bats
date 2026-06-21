#!/usr/bin/env bats
# shellcheck shell=bash
bats_require_minimum_version 1.5.0

setup() {
  export HOME="${BATS_TEST_TMPDIR}"
  export _LIB_ACG_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../lib/acg" && pwd)"
  # shellcheck source=/dev/null
  source "${_LIB_ACG_ROOT}/scripts/lib/cdp.sh"
}

_acg_stub_node_dir() {
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_dir}"
  cat > "${stub_dir}/node" <<'NODE'
#!/usr/bin/env bash
set -euo pipefail
printf 'NODE_PATH=%s\n' "${NODE_PATH:-}"
printf 'ARGS=%s\n' "$*"
if [[ "${1:-}" == "--check" ]]; then
  exit 0
fi
if [[ "${1:-}" == *"acg_session_check.js" ]]; then
  printf 'ACG_SESSION_OK\n'
  exit 0
fi
exit 99
NODE
  chmod +x "${stub_dir}/node"
  printf '%s\n' "${stub_dir}"
}

@test "_cdp_ensure_acg_session: skip flag bypasses node invocation" {
  local stub_dir
  stub_dir="$(_acg_stub_node_dir)"
  PATH="${stub_dir}:$PATH"
  export K3DM_ACG_SKIP_SESSION_CHECK=1

  run --separate-stderr _cdp_ensure_acg_session
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"skipping ACG/Pluralsight session check"* ]]
  [[ "$output" != *"NODE_PATH="* ]]
}

@test "_cdp_ensure_acg_session: fails when session checker script is missing" {
  local old_root="${_LIB_ACG_ROOT}"
  export _LIB_ACG_ROOT="${BATS_TEST_TMPDIR}/missing-lib-acg"

  run --separate-stderr _cdp_ensure_acg_session
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Missing ACG session check script"* ]]

  export _LIB_ACG_ROOT="${old_root}"
}

@test "_cdp_ensure_acg_session: invokes node with NODE_PATH and script path" {
  local stub_dir script_path
  stub_dir="$(_acg_stub_node_dir)"
  PATH="${stub_dir}:$PATH"
  script_path="${_LIB_ACG_ROOT}/../acg_session_check.js"

  run --separate-stderr _cdp_ensure_acg_session
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Checking Pluralsight (ACG) session in Antigravity browser"* ]]
  [[ "$output" == *"ACG_SESSION_OK"* ]]
  [[ "$output" == *"NODE_PATH=${_LIB_ACG_ROOT}/node_modules"* ]]
  [[ "$output" == *"ARGS=${script_path}"* ]]
}

@test "acg_session_check.js --check passes syntax validation" {
  run node --check "${_LIB_ACG_ROOT}/../acg_session_check.js"
  [ "$status" -eq 0 ]
}
