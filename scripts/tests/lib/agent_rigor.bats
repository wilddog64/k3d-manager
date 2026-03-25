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
