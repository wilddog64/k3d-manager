# Copilot PR #26 Review Findings — 2026-05-23

**PR:** [#26](https://github.com/wilddog64/lib-acg/pull/26)
**Fix SHA:** `5774042`

## Finding 1 — `playwright/acg_restart.js` line 44

**What Copilot flagged:** The visibility predicate was only applied to the `visible` boolean check. The follow-up `.find()` that selects the dialog element to click still used only `innerText.includes(...)`. A hidden template node matching the selector could be picked, making the dismiss click a no-op even when `visible` is true.

**Fix applied:**
```javascript
// Before
.find(d => (d.innerText || '').includes('Extend Your Session'));

// After
.find(d =>
  (d.innerText || '').includes('Extend Your Session') &&
  d.offsetParent !== null &&
  getComputedStyle(d).display !== 'none'
);
```

**Root cause:** The visibility guard was added to the detection path but not to the selection path — two separate `evaluate()` calls with inconsistent predicate logic.

**Process note:** When adding visibility guards to browser-JS predicates, apply the guard to all call sites that match on the same selector in the same function — both detection and selection.

## Finding 2 — `docs/bugs/2026-05-23-acg-restart-false-positive-extend-dialog.md` line 89

**What Copilot flagged:** The "Rules" section said "No other files touched" but the PR also updated CHANGELOG and memory-bank, contradicting the repo process guidance (retro 2026-05-19).

**Fix applied:** Changed wording to: "Code change limited to `playwright/acg_restart.js`; CHANGELOG and memory-bank updates may also be required"

**Root cause:** Bug spec template used "No other files touched" as a blanket rule without carve-out for CHANGELOG/memory-bank.

**Process note:** Bug spec template `## Rules` section must use "Code change limited to `<file>`; CHANGELOG and memory-bank updates may also be required" — not "No other files touched".
