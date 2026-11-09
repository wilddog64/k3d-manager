#!/usr/bin/env bats

setup() {
  TEST_ROOT="$(mktemp -d "$BATS_TEST_DIRNAME/../../../.ask-bash-test.XXXXXX")"
  export TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
  export TEST_HOME="$TEST_ROOT/home"
  export TEST_REPO="$TEST_ROOT/repo"
  export TEST_OUTSIDE="$TEST_HOME/outside"
  mkdir -p "$TEST_HOME" "$TEST_REPO" "$TEST_OUTSIDE" "$TEST_REPO/subdir"
  printf 'SAFE_REPO_CONTENT\n' > "$TEST_REPO/README.md"
  printf 'first second\n' > "$TEST_REPO/file"
  printf 'HARMLESS_CANARY\n' > "$TEST_OUTSIDE/canary"
  ln -s "$TEST_OUTSIDE/canary" "$TEST_REPO/link"
  mkdir -p "$TEST_HOME/repo-evil"
  cp "$TEST_OUTSIDE/canary" "$TEST_HOME/repo-evil/canary"
  git -C "$TEST_REPO" init -q
  git -C "$TEST_REPO" add README.md file
  git -C "$TEST_REPO" -c user.name=Test -c user.email=test@example.com commit -qm initial
  export K3DM_REPO_ROOT="$TEST_REPO"
  export K3DM_SHOPPING_CARTS_ROOT="$TEST_ROOT/shopping-carts"
  mkdir -p "$K3DM_SHOPPING_CARTS_ROOT"
  [ "$K3DM_REPO_ROOT" = "$TEST_REPO" ]
}

teardown() {
  rm -rf "$TEST_ROOT"
}

ask_bash() {
  run env HOME="$TEST_HOME" K3DM_REPO_ROOT="$K3DM_REPO_ROOT" \
    K3DM_SHOPPING_CARTS_ROOT="$K3DM_SHOPPING_CARTS_ROOT" \
    K3DM_ASK_OS_SANDBOX="${K3DM_ASK_OS_SANDBOX:-0}" \
    "$BATS_TEST_DIRNAME/../../../bin/k3dm-ask-bash" "$@"
}

assert_denied_without_canary() {
  [ "$status" -ne 0 ]
  [[ "$output" != *HARMLESS_CANARY* ]]
}

@test "ask-bash denies shell-string reads outside the allowed roots" {
  for command in \
    "cat $TEST_OUTSIDE/canary" \
    "cat ../../outside/canary" \
    "cat ~/canary" \
    'cat $HOME/canary' \
    'cat $(echo /x)' \
    "cat $TEST_REPO/link" \
    "cat $TEST_HOME/repo-evil/canary" \
    "cat /tmp/../$TEST_OUTSIDE/canary" \
    "cd; cat canary"; do
    ask_bash -c "$command"
    assert_denied_without_canary
  done
}

@test "ask-bash allows scoped repository diagnostics" {
  ask_bash -c "cat $TEST_REPO/README.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *SAFE_REPO_CONTENT* ]]

  ask_bash -c "git -C $TEST_REPO log -1 --oneline"
  [ "$status" -eq 0 ]

  ask_bash -c "ls /tmp"
  [ "$status" -eq 0 ]

  ask_bash -c "awk '{print \$1}' $TEST_REPO/file"
  [ "$status" -eq 0 ]
  [[ "$output" == *first* ]]
}

@test "ask-bash allows reads when trusted roots contain interpreter names" {
  local python_repo="$TEST_ROOT/repo-python"
  local node_root="$TEST_ROOT/shopping-carts-node"
  mkdir -p "$python_repo" "$node_root"
  printf 'PYTHON_REPO_CONTENT\n' > "$python_repo/README.md"
  printf 'SHOPPING_CARTS_CONTENT\n' > "$node_root/README.md"
  export K3DM_REPO_ROOT="$python_repo"
  export K3DM_SHOPPING_CARTS_ROOT="$node_root"
  [ "$K3DM_REPO_ROOT" = "$python_repo" ]
  [[ "$K3DM_REPO_ROOT" == "$TEST_ROOT"/*python* ]]
  [ "$K3DM_SHOPPING_CARTS_ROOT" = "$node_root" ]
  [[ "$K3DM_SHOPPING_CARTS_ROOT" == "$TEST_ROOT"/*node* ]]

  ask_bash -c "cat $K3DM_REPO_ROOT/README.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *PYTHON_REPO_CONTENT* ]]

  ask_bash -c "cat $K3DM_SHOPPING_CARTS_ROOT/README.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *SHOPPING_CARTS_CONTENT* ]]
}

@test "ask-bash still denies python3 commands with interpreter names in trusted roots" {
  local python_repo="$TEST_ROOT/repo-python"
  mkdir -p "$python_repo"
  export K3DM_REPO_ROOT="$python_repo"
  [ "$K3DM_REPO_ROOT" = "$python_repo" ]
  [[ "$K3DM_REPO_ROOT" == "$TEST_ROOT"/*python* ]]

  ask_bash -c "python3 --version"
  assert_denied_without_canary
}

@test "ask-bash still denies a python3 program inside a trusted root" {
  local python_repo="$TEST_ROOT/repo-python"
  mkdir -p "$python_repo"
  export K3DM_REPO_ROOT="$python_repo"
  [ "$K3DM_REPO_ROOT" = "$python_repo" ]
  [[ "$K3DM_REPO_ROOT" == "$TEST_ROOT"/*python* ]]

  printf '#!/bin/sh\nprintf INSIDE_PYTHON3_RAN\\n\n' > "$K3DM_REPO_ROOT/python3"
  chmod +x "$K3DM_REPO_ROOT/python3"
  [ -x "$K3DM_REPO_ROOT/python3" ]

  ask_bash -c "$K3DM_REPO_ROOT/python3"
  [ "$status" -ne 0 ]
  [[ "$output" != *INSIDE_PYTHON3_RAN* ]]
}

@test "ask-bash still denies a python3 sibling whose path starts with a trusted root" {
  local sibling_root="${TEST_ROOT}/node/python3"
  export K3DM_SHOPPING_CARTS_ROOT="$TEST_ROOT/node"
  mkdir -p "$K3DM_SHOPPING_CARTS_ROOT"
  export K3DM_REPO_ROOT="$TEST_ROOT/node/python"
  mkdir -p "$K3DM_REPO_ROOT"
  printf '#!/bin/sh\nprintf SIBLING_PYTHON3_RAN\\n\n' > "$sibling_root"
  chmod +x "$sibling_root"
  [ "$K3DM_REPO_ROOT" = "$TEST_ROOT/node/python" ]
  [[ "$sibling_root" == "$K3DM_REPO_ROOT"* ]]

  ask_bash -c "$sibling_root"
  [ "$status" -ne 0 ]
  [[ "$output" != *SIBLING_PYTHON3_RAN* ]]
}

@test "ask-bash allows kubectl client version when installed" {
  if ! command -v kubectl >/dev/null 2>&1; then
    skip "kubectl is not installed"
  fi
  ask_bash -c "kubectl version --client"
  [ "$status" -eq 0 ]
}

@test "Darwin OS sandbox denies an allowed-looking HOME read" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "sandbox-exec is Darwin-only"
  fi
  export K3DM_ASK_OS_SANDBOX=1
  printf '#!/bin/bash\ncat "%s/canary"\n' "$TEST_OUTSIDE" > "$TEST_REPO/reader.sh"
  ask_bash -c "bash $TEST_REPO/reader.sh"
  assert_denied_without_canary
  export K3DM_ASK_OS_SANDBOX=0
  ask_bash -c "bash $TEST_REPO/reader.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *HARMLESS_CANARY* ]]
}
