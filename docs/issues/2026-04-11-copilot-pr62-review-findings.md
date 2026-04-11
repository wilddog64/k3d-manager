# Copilot Review Findings — PR #62 (v1.0.5)

**Date:** 2026-04-11
**PR:** [#62](https://github.com/wilddog64/k3d-manager/pull/62) — antigravity decoupling + LDAP Vault KV seeding
**Fixed in:** `26af45df` via [PR #63](https://github.com/wilddog64/k3d-manager/pull/63)

---

## Finding 1 — `scripts/plugins/acg.sh:187` — Private function invoked via dispatcher (BUG)

**What Copilot flagged:** The generated launchd wrapper calls `scripts/k3d-manager _acg_extend_playwright`, but the dispatcher rejects underscore-prefixed (private) names. Runtime failure.

**Fix applied:**
```bash
# Before (launchd wrapper):
"${script_dir}/../k3d-manager" _acg_extend_playwright "${sandbox_url}" \

# After:
"${script_dir}/../k3d-manager" acg_extend_playwright "${sandbox_url}" \
```
Added public wrapper:
```bash
function acg_extend_playwright() {
  _acg_extend_playwright "${@}"
}
```

**Root cause:** Moving `_acg_extend_playwright` from `antigravity.sh` to `acg.sh` kept the underscore prefix private, but the generated wrapper called it through the dispatcher which enforces the public/private contract.

**Process note:** When moving a function that is called via the dispatcher (launchd, cron, any external invocation of `scripts/k3d-manager`), always expose a public wrapper if the implementation is private.

---

## Finding 2 — `scripts/lib/providers/k3s-aws.sh:26` — Help text references private function

**What Copilot flagged:** Step 1 of help text showed `_acg_extend_playwright` (private) — user-facing guidance must reference public names.

**Fix applied:**
```
# Before:
  1. _acg_extend_playwright      — pre-flight TTL extend

# After:
  1. acg_extend_playwright       — pre-flight TTL extend
```

---

## Finding 3 — `.github/copilot-instructions.md:19` — Stale browser automation section

**What Copilot flagged:** Listed `antigravity_acg_extend` (removed this release) as an export; stated `_browser_launch` calls `n()` internally (wrong — it calls `_antigravity_browser_ready`).

**Fix applied:** Applied Copilot's suggestion verbatim.

---

## Findings 4–6 — `README.md`, `docs/releases.md`, `CHANGE.md` — Misleading rename description

**What Copilot flagged:** Release notes said `_acg_extend_playwright` was "moved" but the prior public function was `antigravity_acg_extend`. Readers couldn't correlate the change.

**Fix applied:** All three updated to: `antigravity_acg_extend` renamed/moved to `acg_extend_playwright` in `acg.sh`.

---

## Finding 7 — `.clinerules:5` — Typos

**What Copilot flagged:** `caude` → `Claude`; `a 8,192` → `an 8,192`.

**Fix applied:** Applied Copilot's suggestion verbatim.

---

## Root Cause (meta)

PR #62 was merged before Copilot posted its review — CI completed first, Claude checked for inline comments (empty), and merged. Copilot review runs asynchronously and arrived ~2 minutes after CI. Fix: wait for `gh api .../pulls/<n>/reviews` to show a Copilot entry before merging.

**New memory rule saved:** `feedback_copilot_review_wait.md`
