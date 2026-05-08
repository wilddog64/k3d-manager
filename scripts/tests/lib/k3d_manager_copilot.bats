#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/foundation/scripts/lib/system.sh"
}

@test "fails when prompt requests forbidden shell cd" {
  export_stubs

  export K3DM_ENABLE_AI=1
  _safe_path() { :; }
  _ensure_copilot_cli() { :; }
  _k3dm_repo_root() { echo "$SCRIPT_DIR"; }
  export -f _safe_path _ensure_copilot_cli _k3dm_repo_root

  run _ai_agent_review -p "run shell(cd ..)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"shell(cd"* ]]
  [ ! -s "$RUN_LOG" ]
}

@test "invokes copilot with scoped prompt and guard rails" {
  export_stubs

  export K3DM_ENABLE_AI=1
  _safe_path() { echo safe_path >> "$RUN_LOG"; }
  _ensure_copilot_cli() { echo ensure_cli >> "$RUN_LOG"; }
  _k3dm_repo_root() { echo "$SCRIPT_DIR"; }
  _run_command() {
    printf '%s\n' "$*" >> "$RUN_LOG"
    return 0
  }
  export -f _safe_path _ensure_copilot_cli _k3dm_repo_root _run_command

  run _ai_agent_review -p "generate summary" --model claude-sonnet-4-5
  [ "$status" -eq 0 ]
  grep -q '^safe_path$' "$RUN_LOG"
  grep -q '^ensure_cli$' "$RUN_LOG"
  grep -F -q -- '--soft -- copilot' "$RUN_LOG"
  grep -q ' -p ' "$RUN_LOG"
  grep -F -q -- "--deny-tool shell(cd ..)" "$RUN_LOG"
  grep -F -q -- "--deny-tool shell(git push)" "$RUN_LOG"
}
