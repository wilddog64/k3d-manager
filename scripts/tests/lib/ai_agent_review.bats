#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329

bats_require_minimum_version 1.5.0

setup() {
  SYSTEM_LIB="${BATS_TEST_DIRNAME}/../../lib/system.sh"
  # shellcheck source=/dev/null
  source "$SYSTEM_LIB"
  : > "$BATS_TEST_TMPDIR/ai_agent_review.log"
}

@test "_ai_agent_review dispatches to _copilot_review with default model" {
  _copilot_review() {
    printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/ai_agent_review.log"
    return 0
  }
  export -f _copilot_review
  unset AI_REVIEW_FUNC AI_REVIEW_MODEL

  run _ai_agent_review --prompt hello
  [ "$status" -eq 0 ]
  grep -q -- "--model gpt-5.4-mini" "$BATS_TEST_TMPDIR/ai_agent_review.log"
  grep -q -- "--prompt hello" "$BATS_TEST_TMPDIR/ai_agent_review.log"

  unset -f _copilot_review
}

@test "_ai_agent_review uses AI_REVIEW_MODEL when set" {
  _copilot_review() {
    printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/ai_agent_review.log"
    return 0
  }
  export -f _copilot_review
  export AI_REVIEW_FUNC=copilot
  export AI_REVIEW_MODEL=claude-sonnet-4-6

  run _ai_agent_review --prompt hello
  [ "$status" -eq 0 ]
  grep -q -- "--model claude-sonnet-4-6" "$BATS_TEST_TMPDIR/ai_agent_review.log"

  unset -f _copilot_review
  unset AI_REVIEW_FUNC AI_REVIEW_MODEL
}

@test "_ai_agent_review errors on unknown AI_REVIEW_FUNC" {
  export AI_REVIEW_FUNC=unknown_backend

  run _ai_agent_review --prompt hello
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown AI_REVIEW_FUNC"* ]]

  unset AI_REVIEW_FUNC
}
