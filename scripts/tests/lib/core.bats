#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329

setup() {
  CORE_LIB="${BATS_TEST_DIRNAME}/../../lib/core.sh"
}

_make_test_script() {
  local target="$1"
  cat <<SCRIPT > "$target"
#!/usr/bin/env bash
source "$CORE_LIB"
SCRIPT_DIR="\$(_resolve_script_dir)"
printf '%s\n' "\$SCRIPT_DIR"
SCRIPT
  chmod +x "$target"
}

@test "_resolve_script_dir returns absolute path" {
  test_dir="${BATS_TEST_TMPDIR}/direct"
  mkdir -p "$test_dir"
  script_path="$test_dir/original.sh"
  _make_test_script "$script_path"

  run "$script_path"
  [ "$status" -eq 0 ]
  expected="$(cd "$test_dir" && pwd -P)"
  [ "$output" = "$expected" ]
}

@test "_resolve_script_dir resolves symlinked script from different directory" {
  real_dir="${BATS_TEST_TMPDIR}/real"
  link_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$real_dir" "$link_dir"
  script_path="$real_dir/original.sh"
  _make_test_script "$script_path"
  link_path="$link_dir/link.sh"
  ln -sf "$script_path" "$link_path"

  run "$link_path"
  [ "$status" -eq 0 ]
  expected="$(cd "$real_dir" && pwd -P)"
  [ "$output" = "$expected" ]
}

# ── _detect_platform ────────────────────────────────────────────────────────

@test "_detect_platform: returns 'mac' on macOS" {
  run bash -c '
    source "$1"
    _is_mac()          { return 0; }
    _is_wsl()          { return 1; }
    _is_debian_family(){ return 1; }
    _is_redhat_family(){ return 1; }
    _is_linux()        { return 1; }
    _detect_platform
  ' _ "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "mac" ]
}

@test "_detect_platform: returns 'wsl' on WSL" {
  run bash -c '
    source "$1"
    _is_mac()          { return 1; }
    _is_wsl()          { return 0; }
    _is_debian_family(){ return 1; }
    _is_redhat_family(){ return 1; }
    _is_linux()        { return 1; }
    _detect_platform
  ' _ "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "wsl" ]
}

@test "_detect_platform: returns 'debian' on Debian/Ubuntu" {
  run bash -c '
    source "$1"
    _is_mac()          { return 1; }
    _is_wsl()          { return 1; }
    _is_debian_family(){ return 0; }
    _is_redhat_family(){ return 1; }
    _is_linux()        { return 1; }
    _detect_platform
  ' _ "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "debian" ]
}

@test "_detect_platform: returns 'redhat' on RHEL/Fedora" {
  run bash -c '
    source "$1"
    _is_mac()          { return 1; }
    _is_wsl()          { return 1; }
    _is_debian_family(){ return 1; }
    _is_redhat_family(){ return 0; }
    _is_linux()        { return 1; }
    _detect_platform
  ' _ "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "redhat" ]
}

@test "_detect_platform: returns 'linux' on generic Linux" {
  run bash -c '
    source "$1"
    _is_mac()          { return 1; }
    _is_wsl()          { return 1; }
    _is_debian_family(){ return 1; }
    _is_redhat_family(){ return 1; }
    _is_linux()        { return 0; }
    _detect_platform
  ' _ "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "linux" ]
}

# ── _cluster_provider ────────────────────────────────────────────────────────

@test "_cluster_provider: returns CLUSTER_PROVIDER when set" {
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  CLUSTER_PROVIDER=k3d run _cluster_provider
  [ "$status" -eq 0 ]
  [ "$output" = "k3d" ]
}

@test "_cluster_provider: falls back to K3D_MANAGER_PROVIDER" {
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  unset CLUSTER_PROVIDER
  K3D_MANAGER_PROVIDER=orbstack run _cluster_provider
  [ "$status" -eq 0 ]
  [ "$output" = "orbstack" ]
}

@test "_cluster_provider: falls back to K3DMGR_PROVIDER" {
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  unset CLUSTER_PROVIDER
  unset K3D_MANAGER_PROVIDER
  K3DMGR_PROVIDER=k3s run _cluster_provider
  [ "$status" -eq 0 ]
  [ "$output" = "k3s" ]
}

# ── _deploy_cluster_resolve_provider ─────────────────────────────────────────

@test "_deploy_cluster_resolve_provider: CLI flag takes precedence" {
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  CLUSTER_PROVIDER=k3s _deploy_cluster_resolve_provider "linux" "k3d" 0
  [ "$_DCRS_PROVIDER" = "k3d" ]
}

@test "_deploy_cluster_resolve_provider: force_k3s flag sets k3s" {
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  _deploy_cluster_resolve_provider "linux" "" 1
  [ "$_DCRS_PROVIDER" = "k3s" ]
}

@test "_deploy_cluster_resolve_provider: env override used when no CLI flag" {
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  CLUSTER_PROVIDER=orbstack _deploy_cluster_resolve_provider "linux" "" 0
  [ "$_DCRS_PROVIDER" = "orbstack" ]
}

@test "_deploy_cluster_resolve_provider: K3D_MANAGER_PROVIDER override" {
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  unset CLUSTER_PROVIDER
  K3D_MANAGER_PROVIDER=k3d _deploy_cluster_resolve_provider "linux" "" 0
  [ "$_DCRS_PROVIDER" = "k3d" ]
}

@test "_deploy_cluster_resolve_provider: K3DMGR_PROVIDER override" {
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  unset CLUSTER_PROVIDER K3D_MANAGER_PROVIDER
  K3DMGR_PROVIDER=k3s _deploy_cluster_resolve_provider "linux" "" 0
  [ "$_DCRS_PROVIDER" = "k3s" ]
}

@test "_deploy_cluster_resolve_provider: mac platform defaults to k3d" {
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  unset CLUSTER_PROVIDER K3D_MANAGER_PROVIDER K3DMGR_PROVIDER K3D_MANAGER_CLUSTER_PROVIDER
  _deploy_cluster_resolve_provider "mac" "" 0
  [ "$_DCRS_PROVIDER" = "k3d" ]
}

@test "_deploy_cluster_resolve_provider: non-interactive non-mac defaults to k3d" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/core.sh'
    unset CLUSTER_PROVIDER K3D_MANAGER_PROVIDER K3DMGR_PROVIDER K3D_MANAGER_CLUSTER_PROVIDER
    _info(){ :; }
    _deploy_cluster_resolve_provider 'linux' '' 0
    printf '%s' \"\$_DCRS_PROVIDER\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "k3d" ]
}
