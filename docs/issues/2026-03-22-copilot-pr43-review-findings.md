# Copilot PR #43 Review Findings

**PR:** #43 — `refactor(v0.9.9): if-count allowlist elimination — ldap + vault plugins`
**Fix commit:** `bbfc12e`
**Files:** `scripts/plugins/ldap.sh`, `scripts/plugins/vault.sh`

---

## Findings

### 1. ldap.sh:482 — `$'\n'` literal split across lines
**Finding:** `_LDAP_LDIF_CONTENT+=$'\n'` was split across two lines, injecting a trailing newline + leading spaces into the LDIF string, breaking LDIF block separators.
**Fix:** Collapsed to single line: `_LDAP_LDIF_CONTENT+=$'\n'`
**Root cause:** Code formatter split the line during helper extraction.

### 2. ldap.sh:727 — `search_output` not declared local; `grep -c || echo "0"` double-value bug
**Finding:** `search_output` leaked into global scope; `grep -c ... || echo "0"` could produce `"0\n0"`, breaking arithmetic comparison.
**Fix:** Added `local search_output=""` to declaration; changed `|| echo "0"` to `|| true`.
**Root cause:** Extraction helper forgot to declare the intermediate variable local.

### 3. ldap.sh:708 — Warning message says "skipping seed" in import context
**Finding:** Guard in `_ldap_import_ldif` printed "skipping seed" which is misleading — the function imports, not seeds.
**Fix:** Changed message to "skipping LDIF import".
**Root cause:** Message copy-pasted from `_ldap_seed_ldif_secret` during extraction.

### 4. ldap.sh:1147 — `restore_trace` + `set +x` disables caller's tracing
**Finding:** `(( restore_trace )) && set +x` at end of `deploy_ldap` turns OFF tracing for the sourced caller instead of restoring it. Should be `set -x`.
**Fix:** Changed `set +x` to `set -x` at line 1145.
**Root cause:** Typo during extraction — `+x` vs `-x` inverted.

### 5. ldap.sh:965 — Help text backslashes prevent variable expansion
**Finding:** `\${LDAP_NAMESPACE}` etc. in heredoc printed literal strings instead of runtime defaults.
**Fix:** Removed backslashes so variables expand at call time.
**Root cause:** Backslashes added to protect against unintended expansion during extraction, but heredoc inside `cat <<EOF` expands variables by default.

### 6. vault.sh:471 — `jq -r '.sealed // empty'` misdetects unsealed Vault
**Finding:** `// empty` treats `false` as falsey, returning empty string when Vault is unsealed. Guard `[[ "$sealed" == "false" ]]` then never matches, causing every call to attempt unseal.
**Fix:** Changed to `jq -r '.sealed'` — returns literal `"false"` or `"true"`.
**Root cause:** `// empty` pattern is appropriate for missing keys, not boolean fields.

### 7. vault.sh:491 — `printf` format string split across lines
**Finding:** `printf '%s\n' "$unseal_output"` split to next line, injecting extra whitespace into stderr output.
**Fix:** Collapsed to `printf '%s\n' "$unseal_output" >&2`.
**Root cause:** Code formatter line-wrapped during extraction.

### 8. vault.sh:1596 — `printf` split injects whitespace into vault policy write
**Finding:** Multi-line `printf` format injects trailing space before newline into policy HCL piped to `vault policy write`, potentially corrupting HCL.
**Fix:** Collapsed to `printf '%s\n' "$policy_hcl" |`.
**Root cause:** Same as finding 7 — line-wrap during extraction.

### 9. vault.sh:1707 — Same `printf` split issue in second policy write call
**Finding:** Identical to finding 8 in `_vault_seed_ldap_service_accounts`.
**Fix:** Same as finding 8.
**Root cause:** Same as finding 8.

---

## Process Notes

- **Spec template addition:** Extraction specs must include a `printf` format check — any multi-line `printf '%s` must be written as `printf '%s\n'` on a single line.
- **`// empty` rule:** Never use `jq -r '.field // empty'` on boolean fields; use `jq -r '.field'` and compare against `"true"`/`"false"` strings.
- **`set +x` vs `set -x`:** When restoring xtrace state, `(( restore_trace )) && set -x` re-enables; `set +x` disables. Easy to invert — add a comment: `# re-enable tracing if it was active on entry`.
