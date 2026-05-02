#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export SCRIPT_DIR
  export PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  source "${SCRIPT_DIR}/lib/system.sh"
  source "${PLUGINS_DIR}/copilot.sh"
}

@test "copilot_triage_pod prints help with --help" {
  run copilot_triage_pod --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: copilot_triage_pod"* ]]
}

@test "copilot_triage_pod fails when namespace is missing" {
  run copilot_triage_pod
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: copilot_triage_pod"* ]]
}

@test "copilot_triage_pod fails when pod is missing" {
  run copilot_triage_pod default
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: copilot_triage_pod"* ]]
}

@test "copilot_triage_pod fails when K3DM_ENABLE_AI is not 1" {
  export K3DM_ENABLE_AI=0
  run copilot_triage_pod default my-pod
  unset K3DM_ENABLE_AI
  [ "$status" -eq 1 ]
  [[ "$output" == *"K3DM_ENABLE_AI=1"* ]]
}

@test "copilot_triage_pod invokes _ai_agent_review with kubectl context" {
  export K3DM_ENABLE_AI=1
  kubectl() {
    case "$*" in
      describe\ pod\ -n\ default\ my-pod)
        echo "describe pod -n default my-pod"
        ;;
      logs\ -n\ default\ my-pod\ --previous\ --tail=100)
        echo "previous logs"
        return 0
        ;;
      logs\ -n\ default\ my-pod\ --tail=100)
        echo "current logs"
        return 0
        ;;
    esac
  }
  _ai_agent_review() {
    printf '%s\n' "$*" >> "$RUN_LOG"
    return 0
  }
  export -f kubectl _ai_agent_review

  run copilot_triage_pod default my-pod
  [ "$status" -eq 0 ]
  grep -q -- '--prompt' "$RUN_LOG"
  grep -q 'kubectl describe pod' "$RUN_LOG"
  grep -q 'last 100 log lines' "$RUN_LOG"
}

@test "copilot_draft_spec prints help with --help" {
  run copilot_draft_spec --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: copilot_draft_spec"* ]]
}

@test "copilot_draft_spec fails when description is missing" {
  run copilot_draft_spec
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: copilot_draft_spec"* ]]
}

@test "copilot_draft_spec fails when K3DM_ENABLE_AI is not 1" {
  export K3DM_ENABLE_AI=0
  run copilot_draft_spec "some bug"
  unset K3DM_ENABLE_AI
  [ "$status" -eq 1 ]
  [[ "$output" == *"K3DM_ENABLE_AI=1"* ]]
}

@test "copilot_draft_spec invokes _ai_agent_review with git context" {
  export K3DM_ENABLE_AI=1
  _k3dm_repo_root() {
    echo "$SCRIPT_DIR"
  }
  git() {
    case "$*" in
      -C\ "$SCRIPT_DIR"\ log\ --oneline\ -10)
        echo "abc1234 fix: something"
        ;;
      -C\ "$SCRIPT_DIR"\ diff\ --name-only\ HEAD~3..HEAD)
        echo "scripts/plugins/copilot.sh"
        ;;
      *)
        echo "unexpected git args: $*" >&2
        return 1
        ;;
    esac
  }
  _ai_agent_review() {
    printf '%s\n' "$*" >> "$RUN_LOG"
    return 0
  }
  export -f _k3dm_repo_root git _ai_agent_review

  run copilot_draft_spec "pods crash on restart"
  [ "$status" -eq 0 ]
  grep -q -- '--prompt' "$RUN_LOG"
  grep -q 'pods crash on restart' "$RUN_LOG"
  grep -q 'recent git log' "$RUN_LOG"
}
