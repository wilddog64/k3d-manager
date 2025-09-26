#!/usr/bin/env bats

load '../test_helpers.bash'

setup() {
  init_test_env
  export CLUSTER_PROVIDER=k3s

  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  stub_run_command
}

@test "_install_k3s renders config and manifest" {
  export K3S_INSTALL_DIR="$BATS_TEST_TMPDIR/bin"
  export K3S_DATA_DIR="$BATS_TEST_TMPDIR/data"
  export K3S_CONFIG_DIR="$BATS_TEST_TMPDIR/etc"
  export K3S_CONFIG_FILE="$K3S_CONFIG_DIR/config.yaml"
  export K3S_MANIFEST_DIR="$BATS_TEST_TMPDIR/manifests"
  export K3S_LOCAL_STORAGE="$BATS_TEST_TMPDIR/storage"

  envsubst() {
    python3 -c 'import os, re, sys
data = sys.stdin.read()
pattern = re.compile(r"\$\{([A-Za-z0-9_]+)\}")
sys.stdout.write(pattern.sub(lambda match: os.environ.get(match.group(1), ""), data))'
  }
  export -f envsubst

  _is_mac() { return 1; }
  _is_debian_family() { return 0; }
  _is_redhat_family() { return 1; }
  _is_wsl() { return 1; }
  export -f _is_mac _is_debian_family _is_redhat_family _is_wsl

  _command_exist() {
    case "$1" in
      k3s|systemctl)
        return 1
        ;;
    esac
    command -v "$1" >/dev/null 2>&1
  }
  export -f _command_exist

  _ip() { echo 198.51.100.10; }
  export -f _ip

  _curl() {
    local outfile=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -o)
          outfile="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    [[ -n "$outfile" ]] && printf '#!/bin/sh\nexit 0\n' > "$outfile"
    return 0
  }
  export -f _curl

  _install_k3s mycluster

  [ -f "$K3S_CONFIG_FILE" ]
  [ -d "$K3S_LOCAL_STORAGE" ]
  [ -d "$K3S_MANIFEST_DIR" ]

  run grep -F 'node-name: "mycluster"' "$K3S_CONFIG_FILE"
  [ "$status" -eq 0 ]
  run grep -F 'advertise-address: "198.51.100.10"' "$K3S_CONFIG_FILE"
  [ "$status" -eq 0 ]

  local manifest="$K3S_MANIFEST_DIR/local-path-storage.yaml"
  [ -f "$manifest" ]
  run grep -F "$K3S_LOCAL_STORAGE" "$manifest"
  [ "$status" -eq 0 ]

  run_lines=()
  while IFS= read -r line; do
    run_lines+=("$line")
  done < "$RUN_LOG"
  local found=1
  for line in "${run_lines[@]}"; do
    if [[ "$line" == env\ INSTALL_K3S_EXEC=* ]]; then
      if [[ "$line" == *"--config ${K3S_CONFIG_FILE}"* ]]; then
        found=0
        break
      fi
    fi
  done
  [ "$found" -eq 0 ]
}
