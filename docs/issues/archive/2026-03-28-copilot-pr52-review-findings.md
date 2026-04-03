# Copilot PR #52 Review Findings — 2026-03-28

**PR:** #52 — feat(antigravity): model fallback, ACG session check, nested agent fix (v0.9.17)
**Fix commit:** `5f7058d`

---

## Findings

### 1. `memory-bank/activeContext.md:11` — Wrong model order in text
**Flagged:** Text said `gemini-1.5-flash → 2.0-flash → 2.5-flash` (old ascending order).
**Fix:** Corrected to `gemini-2.5-flash → 2.0-flash → 1.5-flash`.

---

### 2. `scripts/plugins/antigravity.sh:32` — `--approval-mode yolo` always-on violates safety rule
**Flagged:** `_antigravity_gemini_prompt` always passed `--approval-mode yolo` to every gemini call, including `antigravity_poll_task` which uses a web_fetch-only prompt (no file write + no command — violates AGENTS.md/GEMINI.md safety rule).
**Fix:** Made yolo opt-in via `--yolo` flag parameter. Playwright callers (`_antigravity_ensure_github_session`, `_antigravity_ensure_acg_session`, `antigravity_trigger_copilot_review`, `antigravity_acg_extend`) pass `--yolo`. `antigravity_poll_task` does not.
**Root cause:** `--approval-mode yolo` was added globally when fixing nested agent restrictions, without scoping it to Playwright-only prompts.
**Process note:** GEMINI.md safety rule should be checked at the call site, not just in the helper signature. When adding `--approval-mode yolo`, audit every caller.

---

### 3. `scripts/tests/lib/antigravity.bats:58` — Test 13 mock uses wrong model name
**Flagged:** Stub only succeeded for `gemini-1.5-flash`; actual array starts with `gemini-2.5-flash`.
**Fix:** Already fixed in `d4b2687` (applied before Copilot review completed).

---

### 4. `scripts/tests/lib/antigravity.bats:81` — Test 14 fallback mock uses wrong model order
**Flagged:** Stub emitted 429 for `gemini-1.5-flash` first, but actual array tries `gemini-2.5-flash` first.
**Fix:** Already fixed in `d4b2687`.
**Root cause:** BATS tests were written before model order was flipped from ascending to descending.

---

### 5. `scripts/tests/lib/antigravity.bats:31` — `sleep()` not stubbed, causing real 2s delays
**Flagged:** `_antigravity_gemini_prompt` calls `sleep 2` per model attempt; no stub in `setup()` means unit tests incur real delays.
**Fix:** Added `sleep() { :; }` and `export -f sleep` to `setup()` in `5f7058d`.
**Process note:** Any function that calls `sleep` must have `sleep` stubbed in `setup()` to keep unit tests fast.

---

### 6. `scripts/tests/lib/antigravity.bats:141` — Tmpdir test deletes real user directory
**Flagged:** `rm -rf "${HOME}/.gemini/tmp/k3d-manager"` operates on the real `$HOME`, which can delete developer files when running tests locally.
**Fix:** Test now sets `HOME="${BATS_TEST_TMPDIR}"` before sourcing the plugin; all `mkdir` and `rm -rf` operate in the isolated BATS temp dir (`5f7058d`).
**Process note:** Any BATS test that writes or deletes under `$HOME` must override `HOME` to `BATS_TEST_TMPDIR`.

---

### 7. `docs/plans/v0.9.17-antigravity-model-fallback.md:33` — Spec doc model order wrong
**Flagged:** Spec showed old ascending order (`1.5 → 2.0 → 2.5`).
**Fix:** Updated to `2.5 → 2.0 → 1.5` in `5f7058d`.

---

## Summary

| # | File | Finding | Fix |
|---|------|---------|-----|
| 1 | activeContext.md | Wrong model order in text | `5f7058d` |
| 2 | antigravity.sh | `--approval-mode yolo` always-on (violates safety rule) | `5f7058d` |
| 3 | antigravity.bats:58 | Test 13 mock uses wrong model | `d4b2687` |
| 4 | antigravity.bats:81 | Test 14 fallback mock wrong order | `d4b2687` |
| 5 | antigravity.bats:31 | `sleep` not stubbed in setup() | `5f7058d` |
| 6 | antigravity.bats:141 | Tmpdir test deletes real HOME dir | `5f7058d` |
| 7 | model-fallback.md spec | Wrong model order in spec | `5f7058d` |

All 7 findings addressed. All threads resolved.
