# shellcheck shell=bash
#
# doc_hygiene.sh — documentation quality checks for pre-commit
#
# Public API:
#   _doc_hygiene_check [file...]   — check staged files (or supplied file list)
#
# Exit codes: 0 = pass, 1 = violations found

# _dh_strip_fences
# Read stdin, replace content inside fenced code blocks (``` or ~~~) with blank
# lines. Preserves line count so grep -n line numbers remain accurate.
_dh_strip_fences() {
  awk 'BEGIN{in_fence=0; fence_char=""}
       {
         if ($0 ~ /^[[:space:]]*[`~]{3}/) {
           i = 1
           while (i <= length($0) && substr($0, i, 1) ~ /[ \t]/) i++
           c = substr($0, i, 1)
           if (!in_fence) {
             in_fence = 1; fence_char = c; print ""; next
           } else if (c == fence_char) {
             in_fence = 0; fence_char = ""; print ""; next
           }
         }
         if (in_fence) { print "" } else { print }
       }'
}

# _dh_grep FILE PATTERN [--strip-fences]
# Grep FILE for PATTERN. When _DHC_STAGED=1, read content from the git index
# (staged content) rather than the working-tree file.
# When --strip-fences is passed, fenced code block content is replaced with
# blank lines before grepping (line numbers remain accurate).
# Outputs matching lines with line numbers (grep -n format).
_dh_grep() {
  local file="$1"
  local pattern="$2"
  local strip="${3:-}"
  if [[ "${_DHC_STAGED:-0}" -eq 1 ]]; then
    if [[ "$strip" == "--strip-fences" ]]; then
      git show :"$file" 2>/dev/null | _dh_strip_fences | grep -nE -- "$pattern" || true
    else
      git show :"$file" 2>/dev/null | grep -nE -- "$pattern" || true
    fi
  else
    if [[ "$strip" == "--strip-fences" ]]; then
      _dh_strip_fences < "$file" 2>/dev/null | grep -nE -- "$pattern" || true
    else
      grep -nE -- "$pattern" -- "$file" 2>/dev/null || true
    fi
  fi
}

_doc_hygiene_check() {
  local files=("$@")
  local status=0
  local _DHC_STAGED=0

   # If no files supplied, derive from git staged set
   if [[ ${#files[@]} -eq 0 ]]; then
      local staged
      staged="$(git diff --cached --name-only --diff-filter=ACM -- '*.md' '*.yaml' '*.yml' 2>/dev/null || true)"
      [[ -z "$staged" ]] && return 0
      IFS=$'\n' read -r -d '' -a files <<<"$staged" || true
      _DHC_STAGED=1
   fi

   local file
   for file in "${files[@]}"; do
      if [[ "${_DHC_STAGED:-0}" -eq 1 ]]; then
         git cat-file -e :"$file" 2>/dev/null || continue
      else
         [[ -f "$file" ]] || continue
      fi

      # ------------------------------------------------------------------
      # Check 1: placeholder GitHub org URLs (github.com/user/)
      # ------------------------------------------------------------------
      local placeholder_hits
      placeholder_hits="$(_dh_grep "$file" 'github\.com/user/')"
      if [[ -n "$placeholder_hits" ]]; then
         _warn "doc-hygiene: placeholder URL 'github.com/user/' in ${file}:"
         while IFS= read -r hit; do
            _warn "  ${hit}"
         done <<<"$placeholder_hits"
         status=1
      fi

      # ------------------------------------------------------------------
      # Check 2: bare http:// links in markdown (should be https://)
      # Portable boundary: match http:// not preceded by alphanumeric or colon
      # ------------------------------------------------------------------
      if [[ "$file" == *.md ]]; then
         local http_hits
         http_hits="$(_dh_grep "$file" '(^|[^[:alnum:]_:])http://[^)[:space:]]+' --strip-fences)"
         if [[ -n "$http_hits" ]]; then
            _warn "doc-hygiene: bare http:// link (use https://) in ${file}:"
            while IFS= read -r hit; do
               _warn "  ${hit}"
            done <<<"$http_hits"
            status=1
         fi
      fi

      # ------------------------------------------------------------------
      # Check 3: hardcoded private IPs in YAML (non-blocking warning)
      # Covers RFC1918: 10.x.x.x, 172.16-31.x.x, 192.168.x.x
      # Portable boundary: require non-digit before/after the IP
      # ------------------------------------------------------------------
      if [[ "$file" == *.yaml || "$file" == *.yml ]]; then
         local ip_hits
         ip_hits="$(_dh_grep "$file" \
            '(^|[^0-9])(10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+)([^0-9]|$)')"
         if [[ -n "$ip_hits" ]]; then
            _warn "doc-hygiene: hardcoded private IP in ${file} (consider using DNS name):"
            while IFS= read -r hit; do
               _warn "  ${hit}"
            done <<<"$ip_hits"
            # Non-blocking — warn only, do not set status=1
         fi

         # ------------------------------------------------------------------
         # Check 4: hardcoded internal CoreDNS names in YAML (non-blocking warning)
         # Matches: <name>.<namespace>.svc.cluster.local or <name>.<namespace>.svc
         # These only resolve inside the originating cluster — breaks cross-cluster refs
         # ------------------------------------------------------------------
         local dns_hits
         dns_hits="$(_dh_grep "$file" '[a-z0-9-]+\.[a-z0-9-]+\.svc(\.cluster\.local)?')"
         if [[ -n "$dns_hits" ]]; then
            _warn "doc-hygiene: hardcoded internal CoreDNS name in ${file} (breaks cross-cluster — use service discovery or env config):"
            while IFS= read -r hit; do
               _warn "  ${hit}"
            done <<<"$dns_hits"
            # Non-blocking — warn only, do not set status=1
         fi
      fi
   done

   return "$status"
}
