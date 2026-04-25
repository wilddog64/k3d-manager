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
  gemini() { return 0; }
  _info() { :; }
  export -f _ensure_gemini gemini _info

  run _gemini_ensure_github_session
  [ "$status" -eq 0 ]
  unset -f _ensure_gemini gemini _info
}

@test "_gemini_ensure_github_session: returns 1 when gemini fails" {
  _ensure_gemini() { return 0; }
  gemini() { return 1; }
  _info() { :; }
  export -f _ensure_gemini gemini _info

  run _gemini_ensure_github_session
  [ "$status" -eq 1 ]
  unset -f _ensure_gemini gemini _info
}

@test "_gemini_prompt: succeeds on first model" {
  _info() { :; }
  sleep() { :; }
  gemini() {
    [[ "$2" == "gemini-2.5-flash" ]] && echo "ok" && return 0
    return 1
  }
  export -f _info gemini
  source "scripts/plugins/gemini.sh"

  run _gemini_prompt "test prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
  unset -f _info gemini sleep
}

@test "_gemini_prompt: falls back to next model on 429" {
  _info() { :; }
  sleep() { :; }
  gemini() {
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
  export -f _info gemini
  source "scripts/plugins/gemini.sh"

  run _gemini_prompt "test prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
  unset -f _info gemini sleep
}

@test "_gemini_prompt: fails when all models exhausted" {
  _info() { :; }
  _err() { echo "$*"; exit 1; }
  sleep() { :; }
  gemini() { echo "429 RESOURCE_EXHAUSTED rateLimitExceeded"; return 1; }
  export -f _info _err gemini
  source "scripts/plugins/gemini.sh"

  run _gemini_prompt "test prompt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"All gemini models exhausted"* ]]
  unset -f _info _err gemini sleep
}

@test "_gemini_prompt: passes --approval-mode yolo to gemini when --yolo flag given" {
  _info() { :; }
  gemini() {
    local found_yolo=0
    for arg in "$@"; do
      [[ "$arg" == "yolo" ]] && found_yolo=1
    done
    if [[ $found_yolo -ne 1 ]]; then
      echo "missing --approval-mode yolo: $*"
      return 1
    fi
    echo "ok"
    return 0
  }
  export -f _info gemini
  source "scripts/plugins/gemini.sh"

  run _gemini_prompt "test prompt" --yolo
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
  unset -f _info gemini
}

@test "_gemini_prompt: creates workspace temp dir" {
  _info() { :; }
  gemini() { echo "ok"; return 0; }
  export -f _info gemini
  HOME="${BATS_TEST_TMPDIR}"
  source "scripts/plugins/gemini.sh"

  run _gemini_prompt "test prompt"
  [ "$status" -eq 0 ]
  [ -d "${BATS_TEST_TMPDIR}/.gemini/tmp/k3d-manager" ]
  unset -f _info gemini
}
