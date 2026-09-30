#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/system.sh"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  FAKE_ASSET_DIR="${BATS_TEST_TMPDIR}/asset"
  mkdir -p "$FAKE_ASSET_DIR"
  printf '#!/bin/sh\necho v0.7.0\n' > "${FAKE_ASSET_DIR}/kubeconform"
  chmod +x "${FAKE_ASSET_DIR}/kubeconform"
  FAKE_TARBALL="${BATS_TEST_TMPDIR}/fake.tar.gz"
  tar -czf "$FAKE_TARBALL" -C "$FAKE_ASSET_DIR" kubeconform
  FAKE_SHA="$(sha256sum "$FAKE_TARBALL" 2>/dev/null || shasum -a 256 "$FAKE_TARBALL")"
  FAKE_SHA="${FAKE_SHA%% *}"
  export FAKE_TARBALL FAKE_SHA
}

_stub_release_download() {
  _run_command() {
    printf '%s\n' "$*" >> "$RUN_LOG"
    local out="" prev=""
    local arg
    for arg in "$@"; do
      [[ "$prev" == "-o" ]] && out="$arg"
      prev="$arg"
    done
    [[ -n "$out" ]] && cp "$FAKE_TARBALL" "$out"
  }
  _command_exist() {
    case "$1" in
      kubeconform) [[ -x "${HOME}/.local/bin/kubeconform" ]] ;;
      brew) return 1 ;;
      *) command -v "$1" >/dev/null 2>&1 ;;
    esac
  }
  _ensure_local_bin_on_path() { :; }
}

@test "no-op when kubeconform is already installed" {
  export_stubs
  _command_exist() { [[ "$1" == kubeconform ]]; }
  run _ensure_kubeconform
  [ "$status" -eq 0 ]
  [ ! -s "$RUN_LOG" ]
}

@test "prefers Homebrew when available" {
  export_stubs
  brew_done=0
  _command_exist() {
    case "$1" in
      kubeconform) [[ "$brew_done" -eq 1 ]] ;;
      brew) return 0 ;;
      *) return 1 ;;
    esac
  }
  _run_command() {
    printf '%s\n' "$*" >> "$RUN_LOG"
    [[ "$*" == *"brew install kubeconform"* ]] && brew_done=1
    return 0
  }
  _install_kubeconform_from_release() { echo "release used" >> "$RUN_LOG"; return 1; }
  run _ensure_kubeconform
  [ "$status" -eq 0 ]
  grep -q 'brew install kubeconform' "$RUN_LOG"
  ! grep -q 'release used' "$RUN_LOG"
}

@test "installs the pinned release into ~/.local/bin when the checksum matches" {
  export_stubs
  _stub_release_download
  _kubeconform_sha256() { echo "$FAKE_SHA"; }
  run _install_kubeconform_from_release
  [ "$status" -eq 0 ]
  [ -x "${HOME}/.local/bin/kubeconform" ]
  grep -q "releases/download/v${KUBECONFORM_VERSION}/kubeconform-" "$RUN_LOG"
}

@test "refuses a download whose checksum does not match and installs nothing" {
  export_stubs
  _stub_release_download
  _kubeconform_sha256() { echo "0000000000000000000000000000000000000000000000000000000000000000"; }
  run _install_kubeconform_from_release
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "${HOME}/.local/bin/kubeconform" ]
}

@test "every supported platform has a pinned 64-hex checksum" {
  local pair sum
  for pair in darwin-amd64 darwin-arm64 linux-amd64 linux-arm64; do
    sum="$(_kubeconform_sha256 "$pair")"
    [[ "$sum" =~ ^[0-9a-f]{64}$ ]]
  done
  run _kubeconform_sha256 windows-amd64
  [ "$status" -ne 0 ]
}

@test "validate-manifests ensures kubeconform and pins the CRD catalog to a commit" {
  run awk '/^validate-manifests:/,/^$/' "${BATS_TEST_DIRNAME}/../../../Makefile"
  [[ "$output" == *"_ensure_kubeconform"* ]]
  run grep -E '^KUBECONFORM_CRD_CATALOG := .*CRDs-catalog/[0-9a-f]{40}/' "${BATS_TEST_DIRNAME}/../../../Makefile"
  [ "$status" -eq 0 ]
}
