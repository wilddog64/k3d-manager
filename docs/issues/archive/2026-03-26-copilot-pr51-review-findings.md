# Copilot PR #51 Review Findings

**PR:** #51 — feat: Antigravity IDE + CDP browser automation (v0.9.15+v0.9.16)
**Date:** 2026-03-26
**Findings:** 12 total — 7 fixed in this PR, 5 deferred to lib-foundation v0.3.14

---

## Fixed in this PR

### 1. `docs/releases.md` / `CHANGE.md` — version inconsistency
**Finding:** `docs/releases.md` listed v0.9.16 as released but CHANGE.md had `[Unreleased]`.
**Fix:** Versioned both entries — `[v0.9.16] — 2026-03-26` and `[v0.9.15] — 2026-03-25`.

### 2. `docs/api/functions.md:101` — `@playwright/mcp@latest` doc inaccuracy
**Finding:** Docs said `@playwright/mcp@latest` but impl uses `PLAYWRIGHT_MCP_VERSION` pinned default.
**Fix:** Updated doc to describe `PLAYWRIGHT_MCP_VERSION` env var with pinned default behavior.

### 3. `scripts/plugins/antigravity.sh:73` — binary name detection
**Finding:** `antigravity_install` used `antigravity --version` but Homebrew installs `agy` on macOS.
**Fix:** Added `_ag_bin` detection — tries `agy` first, then `antigravity`, then reports unknown.

### 4. `scripts/plugins/antigravity.sh:39` — `_antigravity_launch` missing curl guard
**Finding:** Curl probe in `_antigravity_launch` ran without checking if curl exists — misleading failure.
**Fix:** Added `_command_exist curl` guard with clear error message before the probe.

### 5. `scripts/plugins/antigravity.sh:104` — missing prerequisites in public functions
**Finding:** `antigravity_trigger_copilot_review` and `antigravity_acg_extend` did not call `_ensure_antigravity_ide` or `_ensure_antigravity_mcp_playwright` — running without `antigravity_install` first would fail with unclear errors.
**Fix:** Added both prerequisite calls to each function after `_ensure_antigravity`.

### 6. `scripts/etc/ldap/ldap-password-rotator.sh:122` — unsafe JSON with `printf`
**Finding:** JSON built via `printf '%s'` — passwords with `"`, `\`, or control chars would produce invalid JSON or corrupt vault writes.
**Fix:** Replaced with `vault kv put key=value` pairs — vault CLI handles encoding; no JSON construction needed, no jq dependency required in pod.

### 7. `scripts/lib/agent_rigor.sh:138` — staged/unstaged inconsistency
**Finding:** `changed_sh` filtered to staged `*.sh` only, but bare-sudo scan used `{ git diff --cached; git diff; }` (both staged and unstaged). Inconsistent contract.
**Fix:** Changed bare-sudo scan to `git diff --cached` only — fully staged-only, consistent with `changed_sh` selection. Pre-commit context only ever has staged changes anyway.

---

## Deferred to lib-foundation v0.3.14

These findings are in subtree-managed files (`scripts/lib/foundation/`). Editing them directly would be overwritten on the next subtree pull. Will be fixed upstream.

| # | File | Finding | Tracking |
|---|------|---------|----------|
| 8 | `scripts/lib/foundation/scripts/lib/system.sh:839` | `_ensure_antigravity_ide` checks `antigravity` binary but Homebrew installs `agy` | lib-foundation v0.3.14 |
| 9 | `scripts/lib/foundation/scripts/lib/system.sh:901` | `_antigravity_browser_ready` loops to timeout when curl missing — should fail fast | lib-foundation v0.3.14 |
| 10 | `scripts/lib/agent_rigor.sh:84` | Copilot suggested reverting to unstaged diff — rejected; staged-only is correct pre-commit behavior; test fixed to stage file instead | N/A (intentional) |
| 11 | `scripts/lib/agent_rigor.sh:158` | Tab-indentation scan uses word-splitting `for file in $changed_sh` — should use NUL-delimited loop | lib-foundation v0.3.14 |
| 12 | `scripts/lib/foundation/CHANGE.md:15` + `docs/api/functions.md:161` | `[Unreleased]` for shipped versions; `@latest` doc inaccuracy | lib-foundation v0.3.14 |

---

## Process Note

Subtree file findings should be spec'd as lib-foundation issues at time of discovery — do not patch subtree copies directly. Add to `docs/plans/` as a lib-foundation spec on the next `feat/v0.3.14` session.
