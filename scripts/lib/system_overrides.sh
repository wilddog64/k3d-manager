#!/usr/bin/env bash
# shellcheck disable=SC1090

# Override selected lib-foundation helpers without modifying the subtree.
# Currently extends _run_command with deploy dry-run awareness.

if declare -f _run_command >/dev/null 2>&1 && ! declare -f __k3dm_base_run_command >/dev/null 2>&1; then
  eval "$(declare -f _run_command | sed '1s/_run_command/__k3dm_base_run_command/')"

  _run_command() {
    local -a original_args=("$@")
    local quiet=0 prefer_sudo=0 require_sudo=0 interactive_sudo=0 probe="" soft=0
    local -a probe_args=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--soft) soft=1; shift;;
        --quiet) quiet=1; shift;;
        --prefer-sudo) prefer_sudo=1; shift;;
        --require-sudo) require_sudo=1; shift;;
        --interactive-sudo) interactive_sudo=1; prefer_sudo=1; shift;;
        --probe) probe="$2"; shift 2;;
        --) shift; break;;
        *) break;;
      esac
    done

    local prog="${1:-}"
    shift || true

    if [[ -n "$probe" ]]; then
      read -r -a probe_args <<< "$probe"
    fi

    case "${K3DM_DEPLOY_DRY_RUN:-0}" in
      ''|0)
        __k3dm_base_run_command "${original_args[@]}"
        return $?
        ;;
      *)
        if [[ -z "$prog" ]]; then
          return 0
        fi
        local -a preview=()
        if (( require_sudo || prefer_sudo )); then
          preview+=("sudo" "$prog")
        else
          preview+=("$prog")
        fi
        if (( $# )); then
          preview+=("$@")
        fi
        printf '[dry-run]'
        local arg
        for arg in "${preview[@]}"; do
          printf ' %q' "$arg"
        done
        printf '\n'
        return 0
        ;;
    esac
  }
fi
