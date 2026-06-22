# Bugfix: Azure SP panel renders intermittently — acg_restart `others` exclusion is case-sensitive

**Branch:** `feat/v0.1.8`
**Files:** `playwright/acg_restart.js`

---

## Problem

In `_findRestartButton` (the card-matching loop), the provider-label match is
case-insensitive (`new RegExp(label, 'i')`) but the sibling-provider exclusion uses
`t.includes(p)`, which is **case-sensitive**. If the sandbox card text renders a provider
name in different casing than the literals `['AWS', 'Google Cloud', 'GCP', 'Azure']`
(e.g. `aws`, `azure`), the exclusion silently misses and a card containing another
provider's label can be accepted as the target — the restart button for the wrong
provider could be returned.

**Root cause (line 113):** asymmetric casing — `label` is tested case-insensitively,
`others` is tested case-sensitively.

Flagged by Copilot on k3d-manager PR #94 (subtree-synced copy). Filed upstream per
subtree discipline — the k3d-manager `scripts/lib/acg/` copy must not be edited directly.

---

## Fix

### Change 1 — `playwright/acg_restart.js`: make the `others` exclusion case-insensitive

**Exact old block (line 113):**

```javascript
          if (new RegExp(label, 'i').test(t) && !others.some(p => t.includes(p))) return true;
```

**Exact new block:**

```javascript
          if (new RegExp(label, 'i').test(t) && !others.some(p => new RegExp(p, 'i').test(t))) return true;
```

**Why:** matches the case-insensitivity already used for `label`, so the sibling-provider
exclusion holds regardless of how the card text is cased.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_restart.js` | Case-insensitive `others` exclusion in card match |

---

## Rules

- `node --check playwright/acg_restart.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `others` exclusion uses `new RegExp(p, 'i').test(t)` (case-insensitive)
- [ ] `node --check playwright/acg_restart.js` passes
- [ ] Committed and pushed to `feat/v0.1.8`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(acg-restart): case-insensitive sibling-provider exclusion in card match
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_restart.js` (plus `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.8`
- Do NOT edit the k3d-manager `scripts/lib/acg/` copy — this fix lands here and reaches
  k3d-manager only via `git subtree pull`
