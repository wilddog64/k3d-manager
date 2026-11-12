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

ask_bash_sandboxed() {
  run env -i HOME="$TEST_HOME" PATH="$PATH" \
    K3DM_REPO_ROOT="$K3DM_REPO_ROOT" \
    K3DM_SHOPPING_CARTS_ROOT="$K3DM_SHOPPING_CARTS_ROOT" \
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

@test "M1: with the OS sandbox on, reading a file inside the repository root through ask-bash exits 0 and prints the file" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "sandbox-exec is Darwin-only"
  fi
  [ -d "$TEST_ROOT" ]
  [ "$TEST_HOME" = "$TEST_ROOT/home" ]
  [ -d "$TEST_HOME" ]
  [ "$K3DM_REPO_ROOT" = "$TEST_REPO" ]
  [ -d "$K3DM_REPO_ROOT" ]

  ask_bash_sandboxed -c "cat $TEST_REPO/README.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *SAFE_REPO_CONTENT* ]]
}

@test "M2: with the OS sandbox on, a non-interpreter program in the repository root runs, exits 0 and prints its output, including when its name is written with quotes" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "sandbox-exec is Darwin-only"
  fi
  [ -d "$TEST_ROOT" ]
  [ "$TEST_HOME" = "$TEST_ROOT/home" ]
  [ -d "$TEST_HOME" ]
  [ "$K3DM_REPO_ROOT" = "$TEST_REPO" ]
  [ -d "$K3DM_REPO_ROOT" ]

  printf '#!/bin/sh\nprintf HELPER_PROGRAM_RAN\\n\n' > "$TEST_REPO/helper"
  chmod +x "$TEST_REPO/helper"
  [ -x "$TEST_REPO/helper" ]

  ask_bash_sandboxed -c "$TEST_REPO/helper"
  [ "$status" -eq 0 ]
  [[ "$output" == *HELPER_PROGRAM_RAN* ]]

  ask_bash_sandboxed -c "$TEST_REPO/hel''per"
  [ "$status" -eq 0 ]
  [[ "$output" == *HELPER_PROGRAM_RAN* ]]
}

@test "N1: with the OS sandbox on, an interpreter named with quotes inside the name runs (py''thon3, pe''rl, no''de)" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "sandbox-exec is Darwin-only"
  fi
  [ -d "$TEST_ROOT" ]
  [ "$TEST_HOME" = "$TEST_ROOT/home" ]
  [ -d "$TEST_HOME" ]
  [ "$K3DM_REPO_ROOT" = "$TEST_REPO" ]
  [ -d "$K3DM_REPO_ROOT" ]

  for cmd in \
    "py''thon3 -c \"print('LEAKED_N1')\"" \
    "pe''rl -e \"print 'LEAKED_N1'\"" \
    "no''de -e \"console.log('LEAKED_N1')\""; do
    if [[ "$cmd" == *"no''de"* ]] && ! command -v node >/dev/null 2>&1; then
      continue
    fi
    ask_bash_sandboxed -c "$cmd"
    [ "$status" -ne 0 ]
    [[ "$output" != *LEAKED_N1* ]]
  done
}

@test "N2: with the OS sandbox on, an interpreter named with a backslash inside the name runs (pyth\\on3)" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "sandbox-exec is Darwin-only"
  fi
  [ -d "$TEST_ROOT" ]
  [ "$TEST_HOME" = "$TEST_ROOT/home" ]
  [ -d "$TEST_HOME" ]
  [ "$K3DM_REPO_ROOT" = "$TEST_REPO" ]
  [ -d "$K3DM_REPO_ROOT" ]

  ask_bash_sandboxed -c "pyth\\on3 -c \"print('LEAKED_N2')\""
  [ "$status" -ne 0 ]
  [[ "$output" != *LEAKED_N2* ]]
}

@test "N3: with the OS sandbox on, an interpreter reached by a glob runs (/usr/bin/pyth?n3, or a glob matching a program named python3 inside the root)" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "sandbox-exec is Darwin-only"
  fi
  [ -d "$TEST_ROOT" ]
  [ "$TEST_HOME" = "$TEST_ROOT/home" ]
  [ -d "$TEST_HOME" ]
  [ "$K3DM_REPO_ROOT" = "$TEST_REPO" ]
  [ -d "$K3DM_REPO_ROOT" ]

  ask_bash_sandboxed -c "/usr/bin/pyth?n3 -c \"print('LEAKED_N3_GLOB')\""
  [ "$status" -ne 0 ]
  [[ "$output" != *LEAKED_N3_GLOB* ]]

  printf '#!/bin/sh\nprintf LEAKED_N3_ROOT\\n\n' > "$TEST_REPO/python3"
  chmod +x "$TEST_REPO/python3"
  [ -x "$TEST_REPO/python3" ]

  ask_bash_sandboxed -c "$TEST_REPO/pyth*"
  [ "$status" -ne 0 ]
  [[ "$output" != *LEAKED_N3_ROOT* ]]
}

@test "N4: with the OS sandbox on, a script whose shebang names an interpreter runs" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "sandbox-exec is Darwin-only"
  fi
  [ -d "$TEST_ROOT" ]
  [ "$TEST_HOME" = "$TEST_ROOT/home" ]
  [ -d "$TEST_HOME" ]
  [ "$K3DM_REPO_ROOT" = "$TEST_REPO" ]
  [ -d "$K3DM_REPO_ROOT" ]

  printf '#!/usr/bin/perl\nprint "LEAKED_N4_PERL\\n";\n' > "$TEST_REPO/script.pl"
  chmod +x "$TEST_REPO/script.pl"
  [ -x "$TEST_REPO/script.pl" ]

  ask_bash_sandboxed -c "$TEST_REPO/script.pl"
  [ "$status" -ne 0 ]
  [[ "$output" != *LEAKED_N4_PERL* ]]

  printf '#!/usr/bin/env python3\nprint("LEAKED_N4_PYTHON")\n' > "$TEST_REPO/script.py"
  chmod +x "$TEST_REPO/script.py"
  [ -x "$TEST_REPO/script.py" ]

  ask_bash_sandboxed -c "$TEST_REPO/script.py"
  [ "$status" -ne 0 ]
  [[ "$output" != *LEAKED_N4_PYTHON* ]]
}
