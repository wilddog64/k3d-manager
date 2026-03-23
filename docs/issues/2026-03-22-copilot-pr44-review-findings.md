# Copilot PR #44 Review Findings

**PR:** #44 — `refactor(v0.9.10): if-count allowlist elimination — jenkins plugin`
**Fix commit:** `25e2b2a`
**File:** `scripts/plugins/jenkins.sh`

---

## Findings

### 1 + 4. jenkins.sh:2011-2021 — Duplicate `local` + `export` block for PKI vars
**Finding:** `vault_pki_secret_name` and `vault_pki_leaf_host` were declared `local` and then `export`-ed twice back-to-back in the same scope. The second block was an exact copy of the first, making it unclear which value is authoritative.
**Fix:** Removed the second (duplicate) `local` + `export` block.
**Root cause:** Codex's helper extraction duplicated the initialization block when restructuring `_deploy_jenkins`.

### 2 + 3. jenkins.sh:1276/1285/1350/1359 — Help text mismatch with code default for `JENKINS_VAULT_ENABLED`
**Finding:** The code sets `enable_vault="${JENKINS_VAULT_ENABLED:-1}"` (default: enabled), but the help text in both heredocs said "Deploy Vault (default: disabled)" and "Enable Vault auto-deployment (default: 0)".
**Fix:** Updated all 4 occurrences to show `(default: enabled)` / `(default: 1)` to match the actual code behavior.
**Root cause:** Help text was not updated when the default was changed during refactoring.

---

## Process Notes

- **Spec template addition:** After every helper extraction, verify that all help text defaults match the actual variable defaults in the code (`:-N` fallback value).
- **Duplicate block detection:** When reviewing Codex diffs, scan for back-to-back identical `local`/`export` patterns — a sign of copy-paste during extraction.
