#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export SCRIPT_DIR="${REPO_ROOT}/scripts"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.ssh" "${BATS_TEST_TMPDIR}/bin"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  for tool in gcloud az kubectl k3sup; do
    cat > "${BATS_TEST_TMPDIR}/bin/${tool}" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "${BATS_TEST_TMPDIR}/calls"
case "$*" in
  *"describe"*|*"show"*) exit 1 ;;
  *"publicIps"*) printf '203.0.113.10\n' ;;
esac
exit 0
SH
    chmod +x "${BATS_TEST_TMPDIR}/bin/${tool}"
  done
  cat > "${BATS_TEST_TMPDIR}/bin/ssh" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == -G ]] && exec /usr/bin/ssh "$@"
exit 1
SH
  chmod +x "${BATS_TEST_TMPDIR}/bin/ssh"
  _info() { :; }
  _warn() { printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/warnings"; }
  _dry_run_active() { [[ "${DRY_RUN:-0}" == 1 ]]; }
  _dry_guard() { local label="$1"; shift; _dry_run_active && return 0; "$@"; }
  _run_command() { [[ "$1" == -- ]] && shift; "$@"; }
  export -f _info _warn _dry_run_active _dry_guard _run_command
  source "${SCRIPT_DIR}/lib/foundation/scripts/lib/ssh_fragment.sh"
  source "${SCRIPT_DIR}/lib/providers/k3s-gcp.sh"
  source "${SCRIPT_DIR}/lib/providers/k3s-az.sh"
}

_assert_fixture_paths() {
  [[ "$HOME" == "${BATS_TEST_TMPDIR}"/* ]]
  [[ "$(_ssh_fragment_path)" == "${BATS_TEST_TMPDIR}"/* ]]
  [[ "$(command -v gcloud)" == "${BATS_TEST_TMPDIR}/bin/gcloud" ]]
}

@test "GCP and Azure updates leave a symlinked main config unchanged" {
  _assert_fixture_paths
  local target="${BATS_TEST_TMPDIR}/operator-config"
  printf 'Host operator\n  HostName 192.0.2.1\n' > "$target"
  local before
  before="$(shasum -a 256 "$target")"
  ln -s "$target" "${HOME}/.ssh/config"
  _gcp_update_ssh_config 203.0.113.10 ubuntu /key
  _gcp_update_ssh_config 203.0.113.10 ubuntu /key
  _az_update_ssh_config 203.0.113.11 azureuser /key
  _az_update_ssh_config 203.0.113.11 azureuser /key
  [[ -L "${HOME}/.ssh/config" ]]
  [[ "$(shasum -a 256 "$target")" == "$before" ]]
}

@test "provider updates never create a missing main SSH config" {
  _assert_fixture_paths
  _gcp_update_ssh_config 203.0.113.10 ubuntu /key
  _az_update_ssh_config 203.0.113.11 azureuser /key
  [[ ! -e "${HOME}/.ssh/config" ]]
}

@test "provider writes are idempotent, mode 600, and Azure alias is resolved at call time" {
  _assert_fixture_paths
  _gcp_update_ssh_config 203.0.113.10 ubuntu /key
  _gcp_update_ssh_config 203.0.113.10 ubuntu /key
  export AZ_SSH_CONFIG_HOST=azure-test
  _az_update_ssh_config 203.0.113.11 azureuser /key
  run grep -c '^Host ubuntu-gcp$' "$(_ssh_fragment_path)"
  [ "$output" -eq 1 ]
  grep -q '^Host azure-test$' "$(_ssh_fragment_path)"
  [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$(_ssh_fragment_path)")" = 600 ]
}

@test "GCP teardown preserves ACG ubuntu and dry run preserves fragment bytes" {
  _assert_fixture_paths
  local block="${BATS_TEST_TMPDIR}/block"
  printf 'Host ubuntu\n  HostName 198.51.100.1\n' > "$block"
  _ssh_fragment_upsert ubuntu "$block"
  _gcp_update_ssh_config 203.0.113.10 ubuntu /key
  if declare -F _gcp_remove_ssh_config >/dev/null; then
    _gcp_remove_ssh_config
    grep -q '^Host ubuntu$' "$(_ssh_fragment_path)"
    _gcp_update_ssh_config 203.0.113.10 ubuntu /key
  fi
  grep -q '^Host ubuntu$' "$(_ssh_fragment_path)"
  printf 'Host ubuntu-gcp\n  HostName 203.0.113.10\n' > "${HOME}/.ssh/config"
  local before
  before="$(shasum -a 256 "$(_ssh_fragment_path)")"
  local main_before
  main_before="$(shasum -a 256 "${HOME}/.ssh/config")"
  export GCP_PROJECT=test
  DRY_RUN=1 _provider_k3s_gcp_destroy_cluster --confirm
  [[ "$(shasum -a 256 "$(_ssh_fragment_path)")" == "$before" ]]
  [[ "$(shasum -a 256 "${HOME}/.ssh/config")" == "$main_before" ]]
}

@test "symlink fragment is refused and preflight stops before cloud create" {
  _assert_fixture_paths
  local target="${BATS_TEST_TMPDIR}/target"
  printf 'Host ubuntu\n' > "$target"
  export K3DM_SSH_SANDBOX_FRAGMENT="${HOME}/.ssh/k3dm-sandbox.conf"
  ln -s "$target" "$K3DM_SSH_SANDBOX_FRAGMENT"
  run _gcp_update_ssh_config 203.0.113.10 ubuntu /key
  [ "$status" -ne 0 ]
  run _gcp_remove_ssh_config
  [ "$status" -eq 0 ]
  [[ -L "$K3DM_SSH_SANDBOX_FRAGMENT" ]]
  [[ -f "$target" ]]
  rm "$K3DM_SSH_SANDBOX_FRAGMENT"
  : > "${HOME}/key"; : > "${HOME}/key.pub"
  export GCP_PROJECT=test GCP_SSH_KEY="${HOME}/key"
  run _provider_k3s_gcp_deploy_cluster
  [ "$status" -ne 0 ]
  run _provider_k3s_az_deploy_cluster
  [ "$status" -ne 0 ]
  if [[ -f "${BATS_TEST_TMPDIR}/calls" ]]; then
    run grep -q 'instances create' "${BATS_TEST_TMPDIR}/calls"
    [ "$status" -ne 0 ]
    run grep -q '^az ' "${BATS_TEST_TMPDIR}/calls"
    [ "$status" -ne 0 ]
  fi
}
