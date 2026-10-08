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
  export K3DM_REPO_ROOT="$TEST_HOME"
  ask_bash -c "cat $TEST_OUTSIDE/canary"
  assert_denied_without_canary
  unset K3DM_ASK_OS_SANDBOX
}
