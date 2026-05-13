# shellcheck shell=bash

if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
fi

function _identity_first_pod() {
  local namespace="${1:?namespace required}"
  shift

  local selector pod
  for selector in "$@"; do
    [[ -z "$selector" ]] && continue
    pod="$(_run_command --soft --quiet -- kubectl get pod -n "$namespace" -l "$selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    pod="${pod//$'\n'/}"
    if [[ -n "$pod" ]]; then
      printf '%s\n' "$pod"
      return 0
    fi
  done

  return 1
}

function _identity_secret_field() {
  local namespace="${1:?namespace required}"
  local secret="${2:?secret required}"
  local key="${3:?key required}"
  local raw decoded jsonpath

  printf -v jsonpath '{.data.%s}' "$key"
  raw="$(_run_command --soft --quiet -- kubectl get secret -n "$namespace" "$secret" -o "jsonpath=${jsonpath}" 2>/dev/null || true)"
  raw="${raw//$'\n'/}"
  [[ -z "$raw" ]] && return 1

  decoded="$(printf '%s' "$raw" | base64 --decode 2>/dev/null || printf '%s' "$raw" | base64 -D 2>/dev/null || true)"
  [[ -z "$decoded" ]] && return 1

  printf '%s\n' "$decoded"
}

function _identity_exec_pod() {
  local namespace="${1:?namespace required}"
  local pod="${2:?pod required}"
  local container="${3:-}"
  shift 3

  local -a cmd=(kubectl exec -n "$namespace")
  if [[ -n "$container" ]]; then
    cmd+=(-c "$container")
  fi
  cmd+=("$pod" -- "$@")

  _run_command --quiet -- "${cmd[@]}"
}

function _identity_logs_pod() {
  local namespace="${1:?namespace required}"
  local pod="${2:?pod required}"
  shift 2

  _run_command --quiet -- kubectl logs -n "$namespace" "$pod" "$@"
}
