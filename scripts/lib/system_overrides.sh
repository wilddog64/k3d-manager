#!/usr/bin/env bash
# shellcheck disable=SC1090

# Override selected lib-foundation helpers without modifying the subtree.
# Currently extends _run_command with deploy dry-run awareness.

if declare -f _run_command >/dev/null 2>&1 && ! declare -f __k3dm_base_run_command >/dev/null 2>&1; then
  eval "$(declare -f _run_command | sed '1s/_run_command/__k3dm_base_run_command/')"

  _run_command() {
    local -a original_args=("$@")
    local quiet=0 prefer_sudo=0 require_sudo=0 soft=0

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--soft) soft=1; shift;;
        --quiet) quiet=1; shift;;
        --prefer-sudo) prefer_sudo=1; shift;;
        --require-sudo) require_sudo=1; shift;;
        --interactive-sudo) prefer_sudo=1; shift;;
        --probe) shift 2;;
        --) shift; break;;
        *) break;;
      esac
    done

    local prog="${1:-}"
    shift || true

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

if declare -f _args_have_sensitive_flag >/dev/null 2>&1 && ! declare -f __k3dm_base_args_have_sensitive_flag >/dev/null 2>&1; then
  eval "$(declare -f _args_have_sensitive_flag | sed '1s/_args_have_sensitive_flag/__k3dm_base_args_have_sensitive_flag/')"

  _args_have_sensitive_flag() {
    local arg
    local expect_secret=0

    for arg in "$@"; do
      if (( expect_secret )); then
        return 0
      fi
      case "$arg" in
        --password|--token|--username)
          expect_secret=1
          ;;
        --password=*|--token=*|--username=*|*VAULT_TOKEN=*)
          return 0
          ;;
      esac
    done

    return 1
  }
fi

if declare -f _run_command_handle_failure >/dev/null 2>&1 && ! declare -f __k3dm_base_run_command_handle_failure >/dev/null 2>&1; then
  eval "$(declare -f _run_command_handle_failure | sed '1s/_run_command_handle_failure/__k3dm_base_run_command_handle_failure/')"

  _run_command_handle_failure() {
    local prog="$1" rc="$2" quiet="$3" soft="$4"
    shift 4
    local cmd_str=""
    if _args_have_sensitive_flag "$@"; then
      cmd_str="[redacted command containing secrets]"
      quiet=1
    else
      printf -v cmd_str '%q ' "$@"
    fi

    if (( quiet == 0 )); then
      printf '%s command failed (%d): ' "$prog" "$rc" >&2
      printf '%q ' "$@" >&2
      printf '\n' >&2
    fi

    if (( soft )); then
      return "$rc"
    else
      _err "failed to execute ${cmd_str% }: $rc"
    fi
  }
fi
