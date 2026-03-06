#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/system.sh"
}

@test "no-op when node already installed" {
  export_stubs

  _command_exist() {
    [[ "$1" == node ]]
  }
  export -f _command_exist

  run _ensure_node
  [ "$status" -eq 0 ]
  [ ! -s "$RUN_LOG" ]
}

@test "installs via brew when available" {
  export_stubs

  node_present=0
  _command_exist() {
    case "$1" in
      node) [[ "$node_present" -eq 1 ]] ;;
      brew) return 0 ;;
      *) return 1 ;;
    esac
  }
  _run_command() {
    local payload="$*"
    printf '%s\n' "$payload" >> "$RUN_LOG"
    if [[ "$payload" == *"brew install node"* ]]; then
      node_present=1
    fi
    return 0
  }
  export -f _command_exist _run_command

  run _ensure_node
  [ "$status" -eq 0 ]
  grep -q 'brew install node' "$RUN_LOG"
}

@test "installs via apt-get on Debian systems" {
  export_stubs

  node_present=0
  _command_exist() {
    case "$1" in
      node) [[ "$node_present" -eq 1 ]] ;;
      apt-get) return 0 ;;
      *) return 1 ;;
    esac
  }
  _is_debian_family() { return 0; }
  _is_redhat_family() { return 1; }
  _run_command() {
    local payload="$*"
    printf '%s\n' "$payload" >> "$RUN_LOG"
    if [[ "$payload" == *"apt-get install -y nodejs npm"* ]]; then
      node_present=1
    fi
    return 0
  }
  export -f _command_exist _is_debian_family _run_command

  run _ensure_node
  [ "$status" -eq 0 ]
  grep -q 'apt-get update' "$RUN_LOG"
  grep -q 'apt-get install -y nodejs npm' "$RUN_LOG"
}

@test "installs via dnf on RedHat systems" {
  export_stubs

  node_present=0
  _command_exist() {
    case "$1" in
      node) [[ "$node_present" -eq 1 ]] ;;
      dnf) return 0 ;;
      apt-get) return 1 ;;
      *) return 1 ;;
    esac
  }
  _is_redhat_family() { return 0; }
  _is_debian_family() { return 1; }
  _run_command() {
    local payload="$*"
    printf '%s\n' "$payload" >> "$RUN_LOG"
    if [[ "$payload" == *"dnf install -y nodejs npm"* ]]; then
      node_present=1
    fi
    return 0
  }
  export -f _command_exist _is_redhat_family _run_command

  run _ensure_node
  [ "$status" -eq 0 ]
  grep -q 'dnf install -y nodejs npm' "$RUN_LOG"
}

@test "falls back to release installer when no package manager works" {
  export_stubs

  _command_exist() {
    [[ "$1" == node ]] && return 1
    return 1
  }
  _install_node_from_release() {
    echo "node-release" >> "$RUN_LOG"
    return 0
  }
  _is_debian_family() { return 1; }
  _is_redhat_family() { return 1; }
  export -f _command_exist _install_node_from_release _is_debian_family _is_redhat_family

  run _ensure_node
  [ "$status" -eq 0 ]
  grep -q '^node-release$' "$RUN_LOG"
}
