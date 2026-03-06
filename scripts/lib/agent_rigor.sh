# shellcheck disable=SC1090,SC2034

# Ensure SCRIPT_DIR is defined when this library is sourced directly.
if [[ -z "${SCRIPT_DIR:-}" ]]; then
   SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
fi

function _agent_checkpoint() {
   local label="${1:-operation}"

   if ! declare -f _err >/dev/null 2>&1 || \
      ! declare -f _info >/dev/null 2>&1 || \
      ! declare -f _k3dm_repo_root >/dev/null 2>&1; then
      echo "ERROR: agent_rigor.sh requires system.sh to be sourced first" >&2
      return 1
   fi

   if ! command -v git >/dev/null 2>&1; then
      _err "_agent_checkpoint requires git"
   fi

   local repo_root
   repo_root="$(_k3dm_repo_root 2>/dev/null || true)"
   if [[ -z "$repo_root" ]]; then
      _err "Unable to locate git repository root for checkpoint"
   fi

   if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      _err "_agent_checkpoint must run inside a git repository"
   fi

   local status
   status="$(git -C "$repo_root" status --porcelain 2>/dev/null || true)"
   if [[ -z "$status" ]]; then
      _info "Working tree clean; checkpoint skipped"
      return 0
   fi

   if ! git -C "$repo_root" add -A; then
      _err "Failed to stage files for checkpoint"
   fi

   local message="checkpoint: before ${label}"
   if git -C "$repo_root" commit -am "$message"; then
      _info "Created agent checkpoint: ${message}"
      return 0
   fi

   _err "Checkpoint commit failed; resolve git errors and retry"
}
