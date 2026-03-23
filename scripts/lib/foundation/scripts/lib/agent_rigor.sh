# shellcheck shell=bash

_agent_checkpoint() {
   local label="${1:-operation}"

   if ! command -v git >/dev/null 2>&1; then
      _err "_agent_checkpoint requires git"
   fi

   local repo_root=""
   repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
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

# _agent_audit
#
# Audits staged diffs for safety violations. Requires SCRIPT_DIR to be set by
# the sourcing script (system.sh sets it); override via AGENT_AUDIT_IF_ALLOWLIST_FILE.
_agent_audit() {
   if ! command -v git >/dev/null 2>&1; then
      _warn "git not available; skipping agent audit"
      return 0
   fi

   local allowlist_file="${AGENT_AUDIT_IF_ALLOWLIST_FILE:-${SCRIPT_DIR}/etc/agent/if-count-allowlist}"
   local if_allowlist=""
   if [[ -r "$allowlist_file" ]]; then
      local line
      while IFS= read -r line; do
         line=${line%%#*}
         line="${line#"${line%%[![:space:]]*}"}"
         line="${line%"${line##*[![:space:]]}"}"
         [[ -z "$line" ]] && continue
         if_allowlist+=$'\n'
         if_allowlist+="$line"
      done < "$allowlist_file"
   fi

   local status=0
   local diff_bats
   diff_bats="$(git diff --cached -- '*.bats' 2>/dev/null || true)"
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
   changed_sh="$(
      git diff --cached --name-only -- '*.sh' 2>/dev/null || true
   )"
   if [[ -n "$changed_sh" ]]; then
      local max_if="${AGENT_AUDIT_MAX_IF:-8}"
      local file
      for file in $changed_sh; do
         [[ -f "$file" ]] || continue
         local current_func="" if_count=0 line
         local offenders_lines=""
         while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*function[[:space:]]+ ]]; then
            if [[ -n "$current_func" && $if_count -gt $max_if ]]; then
               local allow_key="${file}:${current_func}"
               if [[ ! $'\n'"$if_allowlist"$'\n' == *$'\n'"$allow_key"$'\n'* ]]; then
                  offenders_lines+="${current_func}:${if_count}"$'\n'
               fi
            fi
               current_func="${line#*function }"
               current_func="${current_func%%(*}"
               current_func="${current_func//[[:space:]]/}"
               if_count=0
            elif [[ $line =~ ^[[:space:]]*if[[:space:]\(] ]]; then
               ((++if_count))
            fi
         done < <(git show :"$file" 2>/dev/null || true)

         if [[ -n "$current_func" && $if_count -gt $max_if ]]; then
            local allow_key="${file}:${current_func}"
            if [[ ! $'\n'"$if_allowlist"$'\n' == *$'\n'"$allow_key"$'\n'* ]]; then
               offenders_lines+="${current_func}:${if_count}"$'\n'
            fi
         fi

         offenders_lines="${offenders_lines%$'\n'}"

         if [[ -n "$offenders_lines" ]]; then
            _warn "Agent audit: $file exceeds if-count threshold in: $offenders_lines"
            status=1
         fi
      done
   fi

   if [[ -n "$changed_sh" ]]; then
      local file
      for file in $changed_sh; do
         [[ -f "$file" ]] || continue
         local bare_sudo
         bare_sudo=$(
            { git diff --cached -- "$file" 2>/dev/null; git diff -- "$file" 2>/dev/null; } \
            | grep '^+' \
            | sed 's/^+//' \
            | grep -E '\bsudo[[:space:]]' \
            | grep -Ev '^[[:space:]]*#' \
            | grep -Ev '^[[:space:]]*_run_command\b' || true)
         if [[ -n "$bare_sudo" ]]; then
            _warn "Agent audit: bare sudo call in $file (use _run_command --prefer-sudo):"
            _warn "$bare_sudo"
            status=1
         fi
      done
   fi

   local staged_diff
   staged_diff="$(git diff --cached 2>/dev/null || true)"
   if [[ -n "$staged_diff" ]]; then
      local cred_lines
      cred_lines=$(grep '^+' <<<"$staged_diff" \
         | sed 's/^+//' \
         | grep -E 'kubectl[[:space:]]+exec\b' \
         | grep -E '\benv[[:space:]]+[A-Z_]+=\S' || true)
      if [[ -n "$cred_lines" ]]; then
         _warn "Agent audit: credential pattern detected in kubectl exec command:"
         _warn "$cred_lines"
         status=1
      fi
   fi

   return "$status"
}

_agent_lint() {
   local gate_var="${AGENT_LINT_GATE_VAR:-ENABLE_AGENT_LINT}"
   if [[ "${!gate_var:-0}" != "1" ]]; then
      return 0
   fi

   local ai_func="${AGENT_LINT_AI_FUNC:-}"
   if [[ -z "$ai_func" ]]; then
      _warn "_agent_lint: AGENT_LINT_AI_FUNC not set; skipping AI lint"
      return 0
   fi

   if ! declare -f "$ai_func" >/dev/null 2>&1; then
      _warn "_agent_lint: AI function '${ai_func}' not defined; skipping"
      return 0
   fi

   if ! command -v git >/dev/null 2>&1; then
      _warn "_agent_lint: git not available; skipping"
      return 0
   fi

   local staged_files
   staged_files="$(git diff --cached --name-only --diff-filter=ACM -- '*.sh' 2>/dev/null || true)"
   if [[ -z "$staged_files" ]]; then
      return 0
   fi

   local rules_file="${SCRIPT_DIR}/etc/agent/lint-rules.md"
   if [[ ! -r "$rules_file" ]]; then
      _warn "_agent_lint: lint rules file missing at $rules_file; skipping"
      return 0
   fi

   local prompt
   prompt="Review the following staged shell files for architectural violations.\n\nRules:\n$(cat "$rules_file")\n\nFiles:\n$staged_files"

   "$ai_func" -p "$prompt"
}
