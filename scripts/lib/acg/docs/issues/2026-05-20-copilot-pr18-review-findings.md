# Copilot PR #18 Review Findings

**PR:** #18 — fix(acg-extend): wait for SPA render after Ghost State re-nav; 30s deleteBtn timeout
**File flagged:** `docs/bugs/2026-05-20-acg-extend-ghost-state-delete-btn-not-found-after-spa-nav.md`

---

## Finding 1 — Files Changed table incomplete (line 4 / line 79)

**What Copilot flagged:** The `**Files:**` header and `## Files Changed` table only listed `playwright/acg_extend.js`, but the commit also touched `CHANGELOG.md` and the bug doc itself.

**Fix applied:** Added `CHANGELOG.md` and the spec doc itself to the Files Changed table and to the `**Files:**` header line.

**Root cause:** Spec template was written before knowing that CHANGELOG and the bug doc would be committed alongside the code file. The template should list all files the commit will touch.

**Process note:** Bug spec `## Files Changed` must list every file the commit touches — code, CHANGELOG, and the spec doc itself.

---

## Finding 2 — Rules section says "No other files touched" (line 86)

**What Copilot flagged:** `## Rules` said "No other files touched" — inconsistent with CHANGELOG and bug doc both being committed.

**Fix applied:** Changed to `node --check playwright/acg_extend.js — zero errors` only; removed the "No other files touched" rule since it contradicts the actual commit scope.

**Root cause:** Copy-paste from a code-only spec template.

**Process note:** "No other files touched" in `## Rules` should only appear when the commit truly touches zero docs/CHANGELOG. If CHANGELOG and/or a bug doc are committed, remove that line.

---

## Finding 3 — Definition of Done requires memory-bank updates not in this PR (line 96)

**What Copilot flagged:** DoD listed `memory-bank/activeContext.md` and `memory-bank/progress.md` updates, but the Codex commit did not include those updates. lib-acg has its own `memory-bank/` directory and other bug specs treat updating it as part of the lib-acg workflow.

**Fix applied:** Restored the standard DoD checkbox: `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA and task status. The Codex commit was incomplete for not including those updates.

**Root cause:** The spec wrongly asserted memory-bank files live only in k3d-manager. lib-acg has its own memory-bank and those updates should have been part of this commit.

**Process note:** lib-acg bug specs MUST include memory-bank DoD checkboxes. The Codex agent is responsible for updating lib-acg's own `memory-bank/activeContext.md` and `memory-bank/progress.md` as part of the fix commit.

---

## Pre-merge gate missed

PR #18 was merged before Copilot posted its review. The Phase 3 Haiku agent checked `gh api .../pulls/18/comments` immediately after CI completed — Copilot had been tagged but hadn't finished yet. "No comments" was incorrectly treated as "no findings."

**Process rule reinforced:** After CI green, poll `gh api .../pulls/<n>/reviews` until a Copilot review entry appears before merging. Never merge on "empty comments" alone.
