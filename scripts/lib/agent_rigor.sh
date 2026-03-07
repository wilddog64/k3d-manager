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

function _agent_lint() {
   if [[ "${K3DM_ENABLE_AI:-0}" != "1" ]]; then
      return 0
   fi

   if ! command -v git >/dev/null 2>&1; then
      _warn "git not available; skipping agent lint"
      return 0
   fi

   local staged_files
   staged_files="$(git diff --cached --name-only --diff-filter=ACM -- '*.sh' 2>/dev/null || true)"
   if [[ -z "$staged_files" ]]; then
      return 0
   fi

   local rules_file="${SCRIPT_DIR}/etc/agent/lint-rules.md"
   if [[ ! -r "$rules_file" ]]; then
      _warn "Lint rules file missing; skipping agent lint"
      return 0
   fi

   local prompt
   prompt="Review the following staged shell files for architectural violations.\n\nRules:\n$(cat "$rules_file")\n\nFiles:\n$staged_files"

   _k3d_manager_copilot -p "$prompt"
}

function _agent_audit() {
   if ! command -v git >/dev/null 2>&1; then
      _warn "git not available; skipping agent audit"
      return 0
   fi

   local status=0
   local diff_bats
   diff_bats="$(git diff -- '*.bats' 2>/dev/null || true)"
   if [[ -n "$diff_bats" ]]; then
      if grep -q '^-[[:space:]]*assert_' <<<"$diff_bats"; then
         _warn "Agent audit: assertions removed from BATS files"
         status=1
      fi

      local removed_tests added_tests
      removed_tests=$(grep -c '^-[[:space:]]*@test ' <<<"$diff_bats" || true)
      added_tests=$(grep -c '^+[[:space:]]*@test ' <<<"$diff_bats" || true)
      if (( removed_tests > added_tests )); then
         _warn "Agent audit: number of @test blocks decreased in BATS files"
         status=1
      fi
   fi

   local changed_sh
   changed_sh="$(git diff --name-only -- '*.sh' 2>/dev/null || true)"
   if [[ -n "$changed_sh" ]]; then
      local max_if="${AGENT_AUDIT_MAX_IF:-8}"
      local file
      for file in $changed_sh; do
         [[ -f "$file" ]] || continue
         local offenders
         local current_func="" if_count=0 line
         local offenders_lines=""
         while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*function[[:space:]]+ ]]; then
               if [[ -n "$current_func" && $if_count -gt $max_if ]]; then
                  offenders_lines+="${current_func}:${if_count}"$'\n'
               fi
               current_func="${line#*function }"
               current_func="${current_func%%(*}"
               current_func="${current_func//[[:space:]]/}"
               if_count=0
            elif [[ $line =~ ^[[:space:]]*if[[:space:]\(] ]]; then
               ((++if_count))
            fi
         done < "$file"

         if [[ -n "$current_func" && $if_count -gt $max_if ]]; then
            offenders_lines+="${current_func}:${if_count}"$'\n'
         fi

         offenders="${offenders_lines%$'\n'}"

         if [[ -n "$offenders" ]]; then
            _warn "Agent audit: $file exceeds if-count threshold in: $offenders"
            status=1
         fi
      done
   fi

   if [[ -n "$changed_sh" ]]; then
      local file
      for file in $changed_sh; do
         [[ -f "$file" ]] || continue
         local bare_sudo
         bare_sudo=$(git diff -- "$file" 2>/dev/null \
            | grep '^+' \
            | sed 's/^+//' \
            | grep -E '\bsudo[[:space:]]' \
            | grep -v '_run_command\|#' || true)
         if [[ -n "$bare_sudo" ]]; then
            _warn "Agent audit: bare sudo call in $file (use _run_command --prefer-sudo):"
            _warn "$bare_sudo"
            status=1
         fi
      done
   fi

   local diff_sh
   diff_sh="$(git diff --cached -- '*.sh' 2>/dev/null || true)"
   if [[ -n "$diff_sh" ]]; then
      if grep -qE '^\+.*kubectl exec.*(TOKEN|PASSWORD|SECRET|KEY)=' <<<"$diff_sh"; then
         _warn "Agent audit: credential pattern detected in kubectl exec args — use Vault/ESO instead"
         status=1
      fi
   fi

   return "$status"
}
