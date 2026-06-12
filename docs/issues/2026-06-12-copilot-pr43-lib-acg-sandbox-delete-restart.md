# Copilot PR #43 — lib-acg sandbox.js delete+restart logic

**Date:** 2026-06-12
**PR:** wilddog64/lib-acg#43 — `fix(sandbox): Azure SP empty-field delete+restart + 3-attempt reopen (v0.1.6)`
**Fix commit:** `f0bc7e8`

---

## Finding 1 — CHANGELOG.md:10: description says "SP credentials" but trigger is any partial field

**What Copilot flagged:** The CHANGELOG entry said the delete+restart fires when "SP credentials (Application Client ID / Secret) remain empty after 60s", but the actual code fires when `vals.every(...)` returns false (any field still empty) and 60s has elapsed — not specifically when SP fields are missing.

**Fix applied:**
- `CHANGELOG.md` line 10 updated to: "when credential fields are partially populated (at least one field has a value but not all are filled) after 60s — timer starts only once the panel has loaded enough to show some credentials"

**Root cause:** The spec and commit message described the user-visible symptom (SP fields empty) rather than the code's actual trigger condition.

**Process note:** CHANGELOG descriptions must match the code's actual guard condition, not the motivating symptom.

---

## Finding 2 — sandbox.js:241: two defects in delete+restart guard

**What Copilot flagged:**
1. `partialCredsFirstSeen` timer starts when ANY combination of inputs is incomplete — including when 0 fields are populated (initial loading state). This can trigger delete during field loading, not just when SP fields are stuck.
2. `deleteCycleCount++` incremented before confirming `deleteBtn` exists — a transient button-not-found failure consumes a delete cycle.

**Fix applied (commit `f0bc7e8`):**
```js
// Before:
if (partialCredsFirstSeen === 0) partialCredsFirstSeen = Date.now();
if (
  providerLabel === 'Azure' &&
  Date.now() - partialCredsFirstSeen > 60000 &&
  deleteCycleCount < 3
) {
  deleteCycleCount++;
  // ...
  const deleteBtn = await _findScopedButton(...);
  if (deleteBtn) {
    await deleteBtn.click(...)

// After:
if (partialCredsFirstSeen === 0 && vals.some(v => v.trim().length > 0)) partialCredsFirstSeen = Date.now();
if (
  providerLabel === 'Azure' &&
  partialCredsFirstSeen > 0 &&
  Date.now() - partialCredsFirstSeen > 60000 &&
  deleteCycleCount < 3
) {
  const deleteBtn = await _findScopedButton(...);
  if (deleteBtn) {
    deleteCycleCount++;
    await deleteBtn.click(...)
```

**Root cause:** Timer-start condition was not gated on `vals.some()`, and counter increment was placed before the guard that determines whether a delete actually happens.

**Process note:** Counter increments that track "attempts made" must be inside the block that actually performs the attempt — not at the top of the decision block before guard checks.
