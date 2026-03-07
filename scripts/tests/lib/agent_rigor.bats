#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/system.sh"
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/agent_rigor.sh"
}

@test "_agent_checkpoint: fails when git missing" {
  export_stubs
  
  # Stub command to return 1 for git
  command() { 
    if [[ "$1" == "-v" && "$2" == "git" ]]; then return 1; fi
    if [[ "$1" == "git" ]]; then return 1; fi
    builtin command "$@"; 
  }
  export -f command
  
  run _agent_checkpoint
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires git"* ]]
}

@test "_agent_checkpoint: skips when working tree clean" {
  export_stubs
  
  _k3dm_repo_root() { echo "$BATS_TEST_TMPDIR"; }
  git() {
    local args=("$@")
    if [[ "${args[0]}" == "-C" ]]; then
      shift 2
    fi
    case "$1" in
      rev-parse) return 0 ;;
      status) echo ""; return 0 ;;
    esac
    return 1
  }
  export -f _k3dm_repo_root git
  
  run _agent_checkpoint
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working tree clean"* ]]
}

@test "_agent_checkpoint: commits when working tree dirty" {
  export_stubs
  
  _k3dm_repo_root() { echo "$BATS_TEST_TMPDIR"; }
  git() {
    local args=("$@")
    if [[ "${args[0]}" == "-C" ]]; then
      shift 2
    fi
    case "$1" in
      rev-parse) return 0 ;;
      status) echo "M file.sh"; return 0 ;;
      add) return 0 ;;
      commit) return 0 ;;
    esac
    return 1
  }
  export -f _k3dm_repo_root git
  
  run _agent_checkpoint "test op"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created agent checkpoint: checkpoint: before test op"* ]]
}

@test "_agent_lint: skips when AI disabled" {
  export_stubs
  export K3DM_ENABLE_AI=0
  
  if ! declare -f _agent_lint >/dev/null; then
    skip "_agent_lint not implemented yet"
  fi

  run _agent_lint
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_agent_audit: detects test weakening (placeholder)" {
  # This will likely fail if _agent_audit isn't implemented
  if ! declare -f _agent_audit >/dev/null; then
    skip "_agent_audit not implemented yet"
  fi
  
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit: flags bare sudo in unstaged diff" {
  local repo="$BATS_TEST_TMPDIR/repo_sudo"
  git init "$repo"
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "test"
  
  cd "$repo"
  echo "#!/bin/bash" > test.sh
  git add test.sh
  git commit -m "initial"
  
  echo "sudo apt-get install -y curl" >> test.sh
  
  # Stub _k3dm_repo_root to point to our test repo
  _k3dm_repo_root() { echo "$repo"; }
  export -f _k3dm_repo_root
  
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"bare sudo call"* ]]
}

@test "_agent_audit: ignores _run_command sudo in diff" {
  local repo="$BATS_TEST_TMPDIR/repo_run_cmd"
  git init "$repo"
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "test"
  
  cd "$repo"
  echo "#!/bin/bash" > test.sh
  git add test.sh
  git commit -m "initial"
  
  echo "_run_command --prefer-sudo -- apt-get install -y curl" >> test.sh
  
  _k3dm_repo_root() { echo "$repo"; }
  export -f _k3dm_repo_root
  
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit: flags kubectl exec with credential env var in staged diff" {
  local repo="$BATS_TEST_TMPDIR/repo_cred"
  git init "$repo"
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "test"
  
  cd "$repo"
  echo "#!/bin/bash" > test.sh
  git add test.sh
  git commit -m "initial"
  
  echo "kubectl exec pod -- -e TOKEN=abc123 env" >> test.sh
  git add test.sh
  
  _k3dm_repo_root() { echo "$repo"; }
  export -f _k3dm_repo_root
  
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"credential pattern detected"* ]]
}

@test "_agent_audit: passes clean staged diff" {
  local repo="$BATS_TEST_TMPDIR/repo_clean"
  git init "$repo"
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "test"
  
  cd "$repo"
  echo "#!/bin/bash" > test.sh
  git add test.sh
  git commit -m "initial"
  
  echo "echo hello" >> test.sh
  git add test.sh
  
  _k3dm_repo_root() { echo "$repo"; }
  export -f _k3dm_repo_root
  
  run _agent_audit
  [ "$status" -eq 0 ]
}
