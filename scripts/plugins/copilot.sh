#!/usr/bin/env bash
# scripts/plugins/copilot.sh

function copilot_triage_pod() {
  local namespace="${1:-}"
  local pod="${2:-}"

  if [[ "$namespace" == "-h" || "$namespace" == "--help" ]]; then
    echo "Usage: copilot_triage_pod <namespace> <pod-name>"
    return 0
  fi

  if [[ -z "$namespace" || -z "$pod" ]]; then
    _err "Usage: copilot_triage_pod <namespace> <pod-name>"
  fi

  if [[ "${K3DM_ENABLE_AI:-0}" != "1" ]]; then
    _err "Copilot CLI is disabled. Set K3DM_ENABLE_AI=1 to enable AI tooling."
  fi

  local context
  context="$(
    echo "=== kubectl describe pod ==="
    kubectl describe pod -n "$namespace" "$pod" 2>&1 || true
    echo ""
    echo "=== last 100 log lines ==="
    kubectl logs -n "$namespace" "$pod" --previous --tail=100 2>&1 || \
      kubectl logs -n "$namespace" "$pod" --tail=100 2>&1 || true
  )"

  _ai_agent_review --prompt \
    "Diagnose this Kubernetes pod failure and suggest a fix. Do not run any commands.\n\n${context}"
}

function copilot_draft_spec() {
  local description="${1:-}"

  if [[ "$description" == "-h" || "$description" == "--help" ]]; then
    echo "Usage: copilot_draft_spec '<short bug description>'"
    return 0
  fi

  if [[ -z "$description" ]]; then
    _err "Usage: copilot_draft_spec '<short bug description>'"
  fi

  if [[ "${K3DM_ENABLE_AI:-0}" != "1" ]]; then
    _err "Copilot CLI is disabled. Set K3DM_ENABLE_AI=1 to enable AI tooling."
  fi

  local repo_root
  repo_root="$(_k3dm_repo_root 2>/dev/null || true)"

  local context
  context="$(
    echo "=== recent git log ==="
    git -C "${repo_root:-.}" log --oneline -10 2>/dev/null || true
    echo ""
    echo "=== recently changed files ==="
    git -C "${repo_root:-.}" diff --name-only HEAD~3..HEAD 2>/dev/null || true
  )"

  _ai_agent_review --prompt \
    "Write a docs/bugs/ spec for the following bug in k3d-manager. Use this format: ## Root Cause, ## What to Change (with Before/After code blocks), ## Definition of Done (checkbox list). Do not run any commands.\n\nBug: ${description}\n\nContext:\n${context}"
}
