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

# _agent_audit_is_python <path> <rev>
_agent_audit_is_python() {
   local path="$1" rev="${2:-}" first_line=""
   [[ "$path" == *.py ]] && return 0
   if [[ -n "$rev" ]]; then
      first_line="$(git show "$rev:$path" 2>/dev/null | head -n 1 || true)"
   else
      first_line="$(git show ":$path" 2>/dev/null | head -n 1 || true)"
   fi
   [[ "$first_line" =~ ^#!.*python ]]
}

# _agent_audit_is_py_test <path>
_agent_audit_is_py_test() {
   local path="$1" base="${1##*/}" globs="${AGENT_AUDIT_PY_TEST_GLOB:-*/tests/* test_*.py *_test.py}"
   local -a patterns=()
   local pattern
   read -r -a patterns <<< "$globs"
   for pattern in "${patterns[@]}"; do
      # shellcheck disable=SC2053
      [[ "$path" == $pattern || "$base" == $pattern ]] && return 0
   done
   return 1
}

# _agent_audit_py_files
_agent_audit_py_files() {
   local path prefix
   while IFS= read -r -d '' path; do
      prefix=A
      if ! git cat-file -e ":$path" 2>/dev/null; then
         prefix=D
      fi
      printf '%s%s\0' "$prefix" "$path"
   done < <(git diff --cached --name-only --no-renames -z 2>/dev/null || true)
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
      while IFS= read -r -d '' file; do
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
      done < <(git diff --cached --name-only -z -- '*.sh' 2>/dev/null || true)
   fi

   if [[ -n "$changed_sh" ]]; then
      local file
      while IFS= read -r -d '' file; do
         [[ -f "$file" ]] || continue
         local bare_sudo
         bare_sudo=$(
            { git diff --cached -- "$file" 2>/dev/null; git diff -- "$file" 2>/dev/null; } \
            | grep '^+' \
            | sed 's/^+//' \
            | grep -E '\bsudo[[:space:]]' \
            | grep -Ev '^[[:space:]]*#' \
            | grep -Ev '^[[:space:]]*_run_command\b' \
            | grep -Ev '#[[:space:]]*agent-audit:[[:space:]]*remote-sudo[[:space:]]*$' || true)
         if [[ -n "$bare_sudo" ]]; then
            _warn "Agent audit: bare sudo call in $file (use _run_command --prefer-sudo):"
            _warn "$bare_sudo"
            status=1
         fi
      done < <(git diff --cached --name-only -z -- '*.sh' 2>/dev/null || true)
   fi

   if [[ -n "$changed_sh" ]]; then
      local file
      while IFS= read -r -d '' file; do
         [[ -f "$file" ]] || continue
         local tab_lines
         tab_lines=$(git show :"$file" 2>/dev/null | grep -n $'^ *\t' || true)
         if [[ -n "$tab_lines" ]]; then
            _warn "Agent audit: tab indentation in $file — use 2-space indentation:"
            _warn "$tab_lines"
            status=1
         fi
      done < <(git diff --cached --name-only -z -- '*.sh' 2>/dev/null || true)
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

   local allowlist_content=""
   if [[ -n "${AGENT_IP_ALLOWLIST:-}" && -f "${AGENT_IP_ALLOWLIST}" && -r "${AGENT_IP_ALLOWLIST}" ]]; then
      allowlist_content="$(grep -vE '^[[:space:]]*(#|$)' "${AGENT_IP_ALLOWLIST}" || true)"
   fi
   local file
   while IFS= read -r -d '' file; do
      if [[ -n "$allowlist_content" ]] && grep -Fqx -- "$file" <<< "$allowlist_content"; then
         continue
      fi
      local ip_lines
      ip_lines=$(git show :"$file" 2>/dev/null \
         | grep -En '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || true)
      if [[ -n "$ip_lines" ]]; then
         _warn "Agent audit: hardcoded IP address in $file — use a CoreDNS hostname instead:"
         _warn "$ip_lines"
         status=1
      fi
   done < <(git diff --cached --name-only --diff-filter=ACM -z -- '*.yaml' '*.yml' 2>/dev/null || true)

   local py_file py_status py_path
   local py_test_diff="" removed_py_tests=0 added_py_tests=0 removed_py_assertions=""
   while IFS= read -r -d '' py_file; do
      py_status="${py_file%"${py_file#?}"}"
      py_path="${py_file#?}"
      if { [[ "$py_status" == D ]] && _agent_audit_is_python "$py_path" HEAD; } ||
         { [[ "$py_status" == A ]] && _agent_audit_is_python "$py_path" ""; }; then
         _agent_audit_is_py_test "$py_path" || continue
         py_test_diff+="$(git diff --cached --no-renames -- "$py_path" 2>/dev/null || true)"$'\n'
      fi
   done < <(_agent_audit_py_files)
   if [[ -n "$py_test_diff" ]]; then
      removed_py_tests=$(grep -cE '^-[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_' <<<"$py_test_diff" || true)
      added_py_tests=$(grep -cE '^\+[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_' <<<"$py_test_diff" || true)
      if (( removed_py_tests > added_py_tests )); then
         _warn "Agent audit: number of test functions decreased in Python test files"
         status=1
      fi
      removed_py_assertions=$(grep -E '^-[[:space:]]*(assert([[:space:](]|$)|self\.assert)' <<<"$py_test_diff" || true)
      if [[ -n "$removed_py_assertions" ]]; then
         _warn "Agent audit: assertions removed from Python test files"
         status=1
      fi
   fi

   local py="${AGENT_AUDIT_PYTHON:-python3}" py_stderr="" py_available=1
   if ! command -v "$py" >/dev/null 2>&1; then
      _warn "Agent audit: $py not found; skipping Python syntax check"
      py_available=0
   fi
   local py_error=""
   while IFS= read -r -d '' py_file; do
      py_status="${py_file%"${py_file#?}"}"
      py_path="${py_file#?}"
      if [[ "$py_status" == A && "$py_available" -eq 1 ]] &&
         _agent_audit_is_python "$py_path" ""; then
         py_stderr="$(mktemp "${TMPDIR:-/tmp}/agent-audit-python.XXXXXX")"
         if ! git show :"$py_path" | "$py" -c 'import sys; compile(sys.stdin.buffer.read(), sys.argv[1], "exec")' "$py_path" 2>"$py_stderr"; then
            _warn "Agent audit: Python syntax error in $py_path:"
            py_error="$(tail -n 1 "$py_stderr" 2>/dev/null || true)"
            _warn "$py_error"
            status=1
         fi
         rm -f "$py_stderr"
      fi
   done < <(_agent_audit_py_files)

   local -a py_rule_names=(shell-true eval exec sudo sensitive-flag)
   local -a py_rule_patterns=(
      "shell[[:space:]]*=[[:space:]]*True"
      "(^|[^[:alnum:]_.])eval[[:space:]]*\("
      "(^|[^[:alnum:]_.])exec[[:space:]]*\("
      "[\"']sudo[\"']"
      "[\"']--(password|token|username)(=[^\"']*)?[\"']"
   )
   local added_py_lines="" py_rule_index py_rule="" py_rule_lines="" allow_re="" line
   while IFS= read -r -d '' py_file; do
      py_status="${py_file%"${py_file#?}"}"
      py_path="${py_file#?}"
      if [[ "$py_status" == A ]] && _agent_audit_is_python "$py_path" "" &&
         ! _agent_audit_is_py_test "$py_path"; then
         added_py_lines="$(git diff --cached -- "$py_path" 2>/dev/null \
            | grep '^+' | grep -v '^+++' | sed 's/^+//' \
            | grep -Ev '^[[:space:]]*#' || true)"
         for ((py_rule_index=0; py_rule_index<${#py_rule_names[@]}; py_rule_index++)); do
            py_rule="${py_rule_names[$py_rule_index]}"
            py_rule_lines=""
            allow_re="#[[:space:]]*agent-audit:[[:space:]]*allow[[:space:]]+${py_rule}[[:space:]]+[^[:space:]]"
            while IFS= read -r line; do
               [[ -z "$line" ]] && continue
               if [[ "$line" =~ ${py_rule_patterns[$py_rule_index]} ]] && [[ ! "$line" =~ $allow_re ]]; then
                  py_rule_lines+="$line"$'\n'
               fi
            done <<< "$added_py_lines"
            if [[ -n "$py_rule_lines" ]]; then
               _warn "Agent audit: $py_rule in $py_path (add '# agent-audit: allow $py_rule <reason>' if intended):"
               _warn "${py_rule_lines%$'\n'}"
               status=1
            fi
         done
      fi
   done < <(_agent_audit_py_files)

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

   local lint_globs="${AGENT_LINT_GLOBS:-*.sh *.js *.md}"
   local -a lint_pathspecs=()
   read -r -a lint_pathspecs <<< "$lint_globs"
   local staged_files
   staged_files="$(git diff --cached --name-only --diff-filter=ACM -- "${lint_pathspecs[@]}" 2>/dev/null || true)"
   if [[ -z "$staged_files" ]]; then
      return 0
   fi

   local rules_file="${SCRIPT_DIR}/etc/agent/lint-rules.md"
   if [[ ! -r "$rules_file" ]]; then
      _warn "_agent_lint: lint rules file missing at $rules_file; skipping"
      return 0
   fi

   local prompt
   prompt="Review the following staged files for architectural violations.\n\nRules:\n$(cat "$rules_file")\n\nFiles:\n$staged_files"

   "$ai_func" -p "$prompt"
}
