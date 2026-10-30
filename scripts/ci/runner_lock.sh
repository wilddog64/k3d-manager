#!/usr/bin/env bash
set -euo pipefail

lock_dir="${E2E_RUNNER_LOCK:-$HOME/.k3dm/e2e/runner.lock}"

usage() {
  printf 'usage: %s acquire | release TOKEN\n' "$0" >&2
  exit 2
}

case "${1:-}" in
  acquire)
    [ "$#" -eq 1 ] || usage
    mkdir -p "$(dirname "$lock_dir")"
    wait_seconds="${CI_RUNNER_LOCK_WAIT:-1800}"
    interval="${CI_RUNNER_LOCK_INTERVAL:-30}"
    [[ "$wait_seconds" =~ ^[0-9]+$ ]] || { printf 'invalid CI_RUNNER_LOCK_WAIT\n' >&2; exit 2; }
    [[ "$interval" =~ ^[0-9]+([.][0-9]+)?$ ]] || { printf 'invalid CI_RUNNER_LOCK_INTERVAL\n' >&2; exit 2; }
    started="$(date -u +%s)"
    while ! mkdir "$lock_dir" 2>/dev/null; do
      now="$(date -u +%s)"
      if (( now - started >= wait_seconds )); then
        holder='holder unknown'
        if [ -f "$lock_dir/meta" ]; then
          holder="$(cat "$lock_dir/meta")"
          [ -n "$holder" ] || holder='holder unknown'
        fi
        printf 'runner busy: %s\n' "$holder" >&2
        exit 1
      fi
      sleep "$interval"
    done
    token="owner=ci-${GITHUB_RUN_ID:-unknown}-${GITHUB_RUN_ATTEMPT:-1} pid=$$ ts=$(date -u +%s)"
    if ! printf '%s\n' "$token" > "$lock_dir/meta"; then
      rmdir "$lock_dir" 2>/dev/null || true
      exit 1
    fi
    printf '%s\n' "$token"
    ;;
  release)
    [ "$#" -eq 2 ] || usage
    token="$2"
    if [ -f "$lock_dir/meta" ] && grep -qxF "$token" "$lock_dir/meta"; then
      rm -rf "$lock_dir"
    fi
    ;;
  *)
    usage
    ;;
esac
