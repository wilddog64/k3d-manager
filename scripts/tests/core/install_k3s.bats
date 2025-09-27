#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load '../test_helpers.bash'

setup() {
  init_test_env
  export CLUSTER_PROVIDER=k3s

  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
  _systemd_available() { return 0; }
  export -f _systemd_available
  stub_run_command
}

@test "_ensure_path_exists uses sudo when available" {
  local parent="$BATS_TEST_TMPDIR/protected"
  local target="$parent/needs-sudo"
  mkdir -p "$parent"
  chmod 000 "$parent"

  : > "$RUN_LOG"

  TARGET_DIR="$target"
  PROTECTED_PARENT="$parent"
  export TARGET_DIR PROTECTED_PARENT

  _sudo_available() { return 0; }
  export -f _sudo_available

  _run_command() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--soft|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --probe) shift 2 ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >> "$RUN_LOG"
    if [[ "$1" == "mkdir" && "$2" == "-p" ]]; then
      chmod 755 "$PROTECTED_PARENT"
      command mkdir -p "$TARGET_DIR"
    fi
    return 0
  }
  export -f _run_command

  _ensure_path_exists "$target"

  read_lines "$RUN_LOG" run_calls
  [ "${run_calls[0]}" = "mkdir -p $target" ]
  [ -d "$target" ]

  chmod 755 "$parent"
  unset -f _run_command
  stub_run_command
}

@test "_ensure_path_exists retries with sudo when passwordless fails" {
  local parent="$BATS_TEST_TMPDIR/protected-interactive"
  local target="$parent/needs-sudo"
  mkdir -p "$parent"
  chmod 000 "$parent"

  RUN_EXIT_CODES=(1)

  sudo_calls_log="$BATS_TEST_TMPDIR/sudo.log"
  : > "$sudo_calls_log"

  sudo() {
    echo "$*" >> "$sudo_calls_log"
    chmod 755 "$parent"
    command mkdir -p "$target"
    return 0
  }
  export -f sudo

  _ensure_path_exists "$target"

  [ -d "$target" ]
  grep -q '^mkdir -p ' "$sudo_calls_log"

  chmod 755 "$parent"
  unset -f sudo
  RUN_EXIT_CODES=()
}

@test "_ensure_path_exists fails when sudo unavailable" {
  local parent="$BATS_TEST_TMPDIR/protected-no-sudo"
  local target="$parent/needs-sudo"
  mkdir -p "$parent"
  chmod 000 "$parent"

  _sudo_available() { return 1; }
  export -f _sudo_available

  RUN_EXIT_CODES=(1)

  run -127 _ensure_path_exists "$target"
  [[ "$output" == *"Cannot create directory '$target'. Create it manually, configure sudo, or set K3S_CONFIG_DIR to a writable path."* ]]

  chmod 755 "$parent"
  unset -f _sudo_available
  RUN_EXIT_CODES=()
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
