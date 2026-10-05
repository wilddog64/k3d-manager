#!/usr/bin/env bats

setup() {
  TEST_REPO="$(mktemp -d)"
  git -C "$TEST_REPO" init >/dev/null
  git -C "$TEST_REPO" config user.email "test@example.com"
  git -C "$TEST_REPO" config user.name "Test User"
  mkdir -p "$TEST_REPO/scripts"
  echo "echo base" > "$TEST_REPO/scripts/base.sh"
  git -C "$TEST_REPO" add scripts/base.sh
  git -C "$TEST_REPO" commit -m "initial" >/dev/null
  export SCRIPT_DIR="$TEST_REPO"
  local lib_dir="${BATS_TEST_DIRNAME}/../../lib"
  # shellcheck source=/dev/null
  source "$lib_dir/system.sh"
  # shellcheck source=/dev/null
  source "$lib_dir/agent_rigor.sh"
  cd "$TEST_REPO" || exit 1
}

teardown() {
  rm -rf "$TEST_REPO"
}

@test "_agent_checkpoint skips when working tree clean" {
  run _agent_checkpoint "test op"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working tree clean"* ]]
}

@test "_agent_checkpoint commits checkpoint when dirty" {
  echo "change" >> scripts/base.sh
  run _agent_checkpoint "dirty op"
  [ "$status" -eq 0 ]
  last_subject=$(git -C "$TEST_REPO" log -1 --pretty=%s)
  [ "$last_subject" = "checkpoint: before dirty op" ]
}

@test "_agent_checkpoint fails outside git repo" {
  tmp="$(mktemp -d)"
  pushd "$tmp" >/dev/null || exit 1
  run _agent_checkpoint "nowhere"
  [ "$status" -ne 0 ]
  popd >/dev/null || true
  rm -rf "$tmp"
}

@test "_agent_audit passes when there are no changes" {
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit detects BATS assertion removal" {
  mkdir -p tests
  local at='@'
  printf '%s\n' "${at}test \"one\" {" "  assert_equal 1 1" "}" > tests/sample.bats
  git add tests/sample.bats
  git commit -m "add bats" >/dev/null
  printf '%s\n' "${at}test \"one\" {" "  echo \"noop\"" "}" > tests/sample.bats
  git add tests/sample.bats
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"assertions removed"* ]]
}

@test "_agent_audit detects @test count decrease" {
  mkdir -p tests
  local at='@'
  printf '%s\n' "${at}test \"one\" { true; }" "${at}test \"two\" { true; }" > tests/count.bats
  git add tests/count.bats
  git commit -m "add count bats" >/dev/null
  printf '%s\n' "${at}test \"one\" { true; }" > tests/count.bats
  git add tests/count.bats
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"number of @test"* ]]
}

@test "_agent_audit flags bare sudo" {
  mkdir -p scripts
  cat <<'SCRIPT' > scripts/demo.sh
function demo() {
   echo ok
}
SCRIPT
  git add scripts/demo.sh
  git commit -m "add demo" >/dev/null
  cat <<'SCRIPT' >> scripts/demo.sh
function needs_sudo() {
   sudo ls
}
SCRIPT
  git add scripts/demo.sh
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"bare sudo call"* ]]
}

@test "_agent_audit flags sudo with inline comment" {
  mkdir -p scripts
  cat <<'SCRIPT' > scripts/comment.sh
function action() {
   sudo apt-get update # refresh packages
}
SCRIPT
  git add scripts/comment.sh
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"bare sudo call"* ]]
}

@test "_agent_audit allows sudo marked agent-audit: remote-sudo" {
  mkdir -p scripts
  cat <<'SCRIPT' > scripts/remote.sh
function action() {
   echo ok
}
SCRIPT
  git add scripts/remote.sh
  git commit -m "add remote action" >/dev/null
  cat <<'SCRIPT' >> scripts/remote.sh
   ssh host "sudo fuser -k -n tcp 8200" # agent-audit: remote-sudo
SCRIPT
  git add scripts/remote.sh
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit still flags sudo when the marker is not the trailing comment" {
  mkdir -p scripts
  cat <<'SCRIPT' > scripts/non_trailing.sh
function action() {
   echo ok
}
SCRIPT
  git add scripts/non_trailing.sh
  git commit -m "add non-trailing action" >/dev/null
  cat <<'SCRIPT' >> scripts/non_trailing.sh
   sudo rm -rf /tmp/x # agent-audit: remote-sudo then more
SCRIPT
  git add scripts/non_trailing.sh
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"bare sudo call"* ]]
}

@test "_agent_audit ignores _run_command sudo usage" {
  mkdir -p scripts
  cat <<'SCRIPT' > scripts/run_cmd.sh
function installer() {
   _run_command --prefer-sudo -- apt-get update
}
SCRIPT
  git add scripts/run_cmd.sh
  git commit -m "add installer" >/dev/null
  cat <<'SCRIPT' > scripts/run_cmd.sh
function installer() {
   _run_command --prefer-sudo -- apt-get install -y curl
}
SCRIPT
  git add scripts/run_cmd.sh
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit passes when if-count below threshold" {
  mkdir -p scripts
  cat <<'SCRIPT' > scripts/if_ok.sh
function nested_ok() {
   if true; then
      if true; then
         if true; then
            echo ok
         fi
      fi
   fi
}
SCRIPT
  git add scripts/if_ok.sh
  git commit -m "add if ok" >/dev/null
  cat <<'SCRIPT' > scripts/if_ok.sh
function nested_ok() {
   if true; then
      if true; then
         if true; then
            echo changed
         fi
      fi
   fi
}
SCRIPT
  git add scripts/if_ok.sh
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit fails when if-count exceeds threshold" {
  mkdir -p scripts
  cat <<'SCRIPT' > scripts/if_fail.sh
function big_func() {
   echo base
}
SCRIPT
  git add scripts/if_fail.sh
  git commit -m "add if fail" >/dev/null
  cat <<'SCRIPT' > scripts/if_fail.sh
function big_func() {
   if true; then
      if true; then
         if true; then
            if true; then
               echo many
            fi
         fi
      fi
   fi
}
SCRIPT
  git add scripts/if_fail.sh
  export AGENT_AUDIT_MAX_IF=2
  run _agent_audit
  unset AGENT_AUDIT_MAX_IF
  [ "$status" -ne 0 ]
  [[ "$output" == *"exceeds if-count threshold"* ]]
}

@test "_agent_audit flags tab indentation in staged .sh file" {
  mkdir -p scripts
  printf 'function tabbed() {\n\techo "tab"\n}\n' > scripts/tabbed.sh
  git add scripts/tabbed.sh
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"tab indentation"* ]]
}

@test "_agent_audit flags mixed space+tab indentation in staged .sh file" {
  mkdir -p scripts
  printf 'function mixed() {\n  \techo "mixed"\n}\n' > scripts/mixed.sh
  git add scripts/mixed.sh
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"tab indentation"* ]]
}

@test "_agent_audit passes with 2-space indentation" {
  mkdir -p scripts
  printf 'function spaced() {\n  echo "spaces"\n}\n' > scripts/spaced.sh
  git add scripts/spaced.sh
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit: tab scan handles filename with spaces" {
  local file="file with spaces.sh"
  printf 'function tabbed_spaces() {\n\techo "tab with spaces filename"\n}\n' > "$file"
  git add "$file"
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"tab indentation"* ]]
  [[ "$output" == *"$file"* ]]
  git reset HEAD -- "$file" >/dev/null 2>&1
  rm -f "$file"
}

@test "_agent_audit: passes when staged yaml has no hardcoded IP" {
  local repo
  repo="$(mktemp -d)"
  trap 'rm -rf "$repo"' RETURN
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  printf 'host: my-service.default.svc.cluster.local\n' > "$repo/values.yaml"
  git -C "$repo" add values.yaml
  (
    cd "$repo"
    run _agent_audit
    [ "$status" -eq 0 ]
  )
}

@test "_agent_audit: fails when staged yaml contains hardcoded IP" {
  local repo
  repo="$(mktemp -d)"
  trap 'rm -rf "$repo"' RETURN
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  printf 'host: 192.168.1.100\n' > "$repo/values.yaml"
  git -C "$repo" add values.yaml
  (
    cd "$repo"
    run _agent_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"hardcoded IP"* ]]
  )
}

@test "_agent_audit: fails when staged yml contains hardcoded IP" {
  local repo
  repo="$(mktemp -d)"
  trap 'rm -rf "$repo"' RETURN
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  printf 'host: 10.0.0.1\n' > "$repo/config.yml"
  git -C "$repo" add config.yml
  (
    cd "$repo"
    run _agent_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"hardcoded IP"* ]]
  )
}

@test "_agent_audit ignores unstaged .sh changes" {
  mkdir -p scripts
  cat <<'SCRIPT' > scripts/unstaged.sh
function clean() {
   echo ok
}
SCRIPT
  git add scripts/unstaged.sh
  git commit -m "add unstaged" >/dev/null
  # Add bare sudo to the file but do NOT stage it
  cat <<'SCRIPT' >> scripts/unstaged.sh
function needs_sudo() {
   sudo rm -rf /tmp/test
}
SCRIPT
  # File has bare sudo but is NOT staged — audit must pass
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit: fails on hardcoded-IP yaml when not in allowlist" {
  local repo
  repo="$(mktemp -d)"
  trap 'rm -rf "$repo"' RETURN
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  printf 'host: 10.0.0.1\n' > "$repo/infra.yaml"
  git -C "$repo" add infra.yaml
  (
    cd "$repo"
    run _agent_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"hardcoded IP"* ]]
  )
}

@test "_agent_audit: passes on hardcoded-IP yaml when path is in allowlist" {
  local repo allowlist
  repo="$(mktemp -d)"
  allowlist="$(mktemp)"
  trap 'rm -rf "$repo" "$allowlist"' RETURN
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  printf 'host: 10.0.0.1\n' > "$repo/infra.yaml"
  git -C "$repo" add infra.yaml
  # Allowlist with a comment, blank line, and the target path
  printf '# this is a comment\n\ninfra.yaml\n' > "$allowlist"
  (
    cd "$repo"
    AGENT_IP_ALLOWLIST="$allowlist" run _agent_audit
    [ "$status" -eq 0 ]
  )
}

@test "_agent_audit: passes on hardcoded-IP yaml when dash-prefix path is in allowlist" {
  local repo allowlist
  repo="$(mktemp -d)"
  allowlist="$(mktemp)"
  trap 'rm -rf "$repo" "$allowlist"' RETURN
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  printf 'host: 10.0.0.1\n' > "$repo/-infra.yaml"
  git -C "$repo" add -- -infra.yaml
  printf '%s\n' '-infra.yaml' > "$allowlist"
  (
    cd "$repo"
    AGENT_IP_ALLOWLIST="$allowlist" run _agent_audit
    [ "$status" -eq 0 ]
  )
}

@test "_agent_audit: fails on hardcoded-IP yaml when dash-prefix path is not allowlisted" {
  local repo
  repo="$(mktemp -d)"
  trap 'rm -rf "$repo"' RETURN
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  printf 'host: 10.0.0.1\n' > "$repo/-infra.yaml"
  git -C "$repo" add -- -infra.yaml
  (
    cd "$repo"
    run _agent_audit
    [ "$status" -eq 1 ]
    [[ "$output" == *"hardcoded IP"* ]]
  )
}

@test "_agent_lint picks up staged .js files" {
  mkdir -p "$TEST_REPO/etc/agent"
  echo "No hardcoded secrets." > "$TEST_REPO/etc/agent/lint-rules.md"
  echo 'console.log("hello");' > "$TEST_REPO/app.js"
  git -C "$TEST_REPO" add app.js
  local log
  log="$(mktemp)"
  _mock_ai() { printf '%s\n' "$@" >> "$log"; }
  export -f _mock_ai
  export ENABLE_AGENT_LINT=1
  export AGENT_LINT_AI_FUNC="_mock_ai"
  _agent_lint
  grep -q "app.js" "$log"
}

@test "_agent_audit detects removed Python test functions" {
  mkdir -p tests
  printf 'def test_one():\n  pass\ndef test_two():\n  pass\n' > tests/test_a.py
  git add tests/test_a.py
  git commit -m "add python tests" >/dev/null
  printf 'def test_one():\n  pass\n' > tests/test_a.py
  git add tests/test_a.py
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"test functions decreased"* ]]
}

@test "_agent_audit detects removed Python assertions" {
  mkdir -p tests
  printf 'def test_one():\n  assert value\n  self.assertEqual(value, value)\n' > tests/test_a.py
  git add tests/test_a.py
  git commit -m "add assertion tests" >/dev/null
  printf 'def test_one():\n  pass\n' > tests/test_a.py
  git add tests/test_a.py
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"assertions removed"* ]]
}

@test "_agent_audit allows added Python test functions" {
  mkdir -p tests
  printf 'def test_one():\n  pass\n' > tests/test_a.py
  git add tests/test_a.py
  git commit -m "add one python test" >/dev/null
  printf 'def test_one():\n  pass\ndef test_two():\n  pass\n' > tests/test_a.py
  git add tests/test_a.py
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit detects deleted Python test files" {
  mkdir -p tests
  printf 'def test_one():\n  assert True\n' > tests/test_a.py
  git add tests/test_a.py
  git commit -m "add deletable python test" >/dev/null
  git rm tests/test_a.py >/dev/null
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"test functions decreased"* ]]
}

@test "_agent_audit detects syntax errors in extensionless Python files" {
  mkdir -p bin
  printf '#!/usr/bin/env python3\ndef broken(:\n  pass\n' > bin/tool
  git add bin/tool
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"bin/tool"* ]]
}

@test "_agent_audit ignores syntax errors in non-Python files" {
  printf 'def broken(:\n  pass\n' > notes.txt
  git add notes.txt
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit compiles the staged Python blob" {
  printf 'def broken(:\n  pass\n' > x.py
  git add x.py
  printf 'def fixed():\n  pass\n' > x.py
  run _agent_audit
  [ "$status" -ne 0 ]
  printf 'def valid():\n  pass\n' > x.py
  git add x.py
  printf 'def broken(:\n  pass\n' > x.py
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit skips Python syntax when configured interpreter is missing" {
  printf 'def broken(:\n  pass\n' > x.py
  git add x.py
  AGENT_AUDIT_PYTHON=/nonexistent/python3 run _agent_audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "_agent_audit detects dangerous Python calls" {
  printf '%s\n' \
    'subprocess.run(cmd, shell=True)' \
    'result = eval("x")' \
    'exec("x")' \
    'command = "sudo"' \
    'flag = "--password=secret"' > app.py
  git add app.py
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"shell-true"* ]]
  [[ "$output" == *"eval"* ]]
  [[ "$output" == *"exec"* ]]
  [[ "$output" == *"sudo"* ]]
  [[ "$output" == *"sensitive-flag"* ]]
}

@test "_agent_audit allows dangerous Python calls with reasons" {
  printf '%s\n' \
    'subprocess.run(cmd, shell=True)  # agent-audit: allow shell-true stubbed in tests' \
    'result = eval("x")  # agent-audit: allow eval stubbed in tests' \
    'exec("x")  # agent-audit: allow exec stubbed in tests' \
    'command = "sudo"  # agent-audit: allow sudo stubbed in tests' \
    'flag = "--password=secret"  # agent-audit: allow sensitive-flag stubbed in tests' > app.py
  git add app.py
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit rejects an allow marker without a reason" {
  printf 'subprocess.run(cmd, shell=True)  # agent-audit: allow shell-true\n' > app.py
  git add app.py
  run _agent_audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"shell-true"* ]]
}

@test "_agent_audit exempts Python test files from dangerous-call checks" {
  mkdir -p tests
  printf 'def test_shell():\n  subprocess.run(cmd, shell=True)\n' > tests/test_a.py
  git add tests/test_a.py
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit ignores guarded Python method names" {
  printf 'model.eval()\nos.execv(path, args)\ncreate_subprocess_exec(cmd)\n' > app.py
  git add app.py
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit ignores commented Python dangerous calls" {
  printf '# subprocess.run(x, shell=True)\n' > app.py
  git add app.py
  run _agent_audit
  [ "$status" -eq 0 ]
}

@test "_agent_audit honors custom Python test globs without shell glob expansion" {
  mkdir -p checks
  printf 'def test_one():\n  pass\n' > checks/x.py
  git add checks/x.py
  git commit -m "add custom python test" >/dev/null
  printf 'def test_one():\n  pass\ndef test_two():\n  pass\n' > checks/x.py
  git add checks/x.py
  touch 'test_*.py'
  AGENT_AUDIT_PY_TEST_GLOB='checks/*' run _agent_audit
  [ "$status" -eq 0 ]
  rm -f 'test_*.py'
}

@test "_agent_lint uses configurable staged Python globs" {
  mkdir -p "$TEST_REPO/etc/agent"
  echo "No violations." > "$TEST_REPO/etc/agent/lint-rules.md"
  echo "print('python')" > "$TEST_REPO/a.py"
  echo "echo shell" > "$TEST_REPO/a.sh"
  git -C "$TEST_REPO" add a.py a.sh
  _mock_ai() { printf '%s\n' "$2"; }
  export -f _mock_ai
  export ENABLE_AGENT_LINT=1 AGENT_LINT_AI_FUNC=_mock_ai AGENT_LINT_GLOBS='*.py'
  run _agent_lint
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.py"* ]]
  [[ "$output" != *"a.sh"* ]]
}

@test "_agent_lint picks up staged .md files" {
  mkdir -p "$TEST_REPO/etc/agent"
  echo "No hardcoded secrets." > "$TEST_REPO/etc/agent/lint-rules.md"
  echo "# Docs" > "$TEST_REPO/README.md"
  git -C "$TEST_REPO" add README.md
  local log
  log="$(mktemp)"
  _mock_ai() { printf '%s\n' "$@" >> "$log"; }
  export -f _mock_ai
  export ENABLE_AGENT_LINT=1
  export AGENT_LINT_AI_FUNC="_mock_ai"
  _agent_lint
  grep -q "README.md" "$log"
}
