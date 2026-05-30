# Copilot PR #13 Review Findings

**PR:** #13 — docs: PR #12 retrospective and Phase 3 completion
**Branch:** feat/acg-gcp-credentials
**Date:** 2026-05-18
**Fix commit:** 95655ae

---

## Finding 1 — Retro header tag mismatch

**File:** `docs/retro/2026-05-17-pr12-retrospective.md` line 1
**Flagged by Copilot:** Comment ID 3263078277

**Before:**
```markdown
# Retrospective — PR #12 (feat/acg-multi-provider)
```

**After:**
```markdown
# Retrospective — PR #12 (fix: acg_extend exit-0 on stale toast)
```

**Root cause:** Header parenthetical used the branch name (`feat/acg-multi-provider`) rather than the actual PR topic. The branch was created for a broader multi-provider milestone but the merged content was a single targeted fix.

**Process note:** Retro headers must use the PR's actual fix description, not the branch name.

---

## Finding 2 — Ambiguous "Merged to" label

**File:** `docs/retro/2026-05-17-pr12-retrospective.md` line 6
**Flagged by Copilot:** Comment ID 3263078258

**Before:**
```markdown
**Merged to:** main
```

**After:**
```markdown
**PR #12 merged to:** main
```

**Root cause:** The label "Merged to" is ambiguous — when reviewed in PR #13 (the current PR), Copilot interpreted it as a claim that PR #13 was already merged. The retro documents PR #12's merge, which happened before this PR was opened.

**Process note:** Retro metadata labels must always reference the PR number they describe to avoid ambiguity when the retro itself is under review.
