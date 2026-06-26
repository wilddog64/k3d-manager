#!/usr/bin/env bats

setup() {
  # Mock global dependencies
  _command_exist() { return 0; }
  _is_mac() { return 0; }
  sleep() { :; }
  export -f _command_exist _is_mac sleep

  # Source the plugin under test
  source "scripts/plugins/gemini.sh"
}

@test "_gemini_ensure_github_session: returns 0 when gemini succeeds" {
  _ensure_gemini() { return 0; }
  agy() { return 0; }
  _info() { :; }
  export -f _ensure_gemini agy _info

  run _gemini_ensure_github_session
  [ "$status" -eq 0 ]
  unset -f _ensure_gemini agy _info
}

@test "_gemini_ensure_github_session: returns 1 when gemini fails" {
  _ensure_gemini() { return 0; }
  agy() { return 1; }
  _info() { :; }
  export -f _ensure_gemini agy _info

  run _gemini_ensure_github_session
  [ "$status" -eq 1 ]
  unset -f _ensure_gemini agy _info
}

@test "_agy_prompt: succeeds on first model" {
  _info() { :; }
  sleep() { :; }
  agy() {
    [[ "$2" == "gemini-2.5-flash" ]] && echo "ok" && return 0
    return 1
  }
  export -f _info agy
  source "scripts/plugins/gemini.sh"

  run _agy_prompt "test prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
  unset -f _info agy sleep
}

@test "_agy_prompt: falls back to next model on 429" {
  _info() { :; }
  sleep() { :; }
  agy() {
    if [[ "$2" == "gemini-2.5-flash" ]]; then
      echo "429 RESOURCE_EXHAUSTED rateLimitExceeded"
      return 1
    fi
    if [[ "$2" == "gemini-2.0-flash" ]]; then
      echo "ok"
      return 0
    fi
    return 1
  }
  export -f _info agy
  source "scripts/plugins/gemini.sh"

  run _agy_prompt "test prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
  unset -f _info agy sleep
}

@test "_agy_prompt: fails when all models exhausted" {
  _info() { :; }
  _err() { echo "$*"; exit 1; }
  sleep() { :; }
  agy() { echo "429 RESOURCE_EXHAUSTED rateLimitExceeded"; return 1; }
  export -f _info _err agy
  source "scripts/plugins/gemini.sh"

  run _agy_prompt "test prompt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"All agy models exhausted"* ]]
  unset -f _info _err agy sleep
}

@test "_agy_prompt: passes --dangerously-skip-permissions to agy when requested" {
  _info() { :; }
  agy() {
    local found_skip_permissions=0
    for arg in "$@"; do
      [[ "$arg" == "--dangerously-skip-permissions" ]] && found_skip_permissions=1
    done
    if [[ $found_skip_permissions -ne 1 ]]; then
      echo "missing --dangerously-skip-permissions: $*"
      return 1
    fi
    echo "ok"
    return 0
  }
  export -f _info agy
  source "scripts/plugins/gemini.sh"

  run _agy_prompt "test prompt" --dangerously-skip-permissions
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
  unset -f _info agy
}

@test "_agy_prompt: creates workspace temp dir" {
  _info() { :; }
  agy() { echo "ok"; return 0; }
  export -f _info agy
  HOME="${BATS_TEST_TMPDIR}"
  source "scripts/plugins/gemini.sh"

  run _agy_prompt "test prompt"
  [ "$status" -eq 0 ]
  [ -d "${BATS_TEST_TMPDIR}/.gemini/tmp/k3d-manager" ]
  unset -f _info agy
}
