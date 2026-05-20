# Copilot PR #16 Review Findings

**PR:** #16 — fix(acg-extend): narrow midnight-wrap guard so expired sandboxes report negative TTL
**Date:** 2026-05-20
**Findings addressed:** 3 of 9 (6 were stale post-merge)

---

## Finding 1 — Midnight-wrap condition inverted for 11:59PM→12:30AM edge case

**File:** `playwright/acg_extend.js:208`

**What Copilot flagged:** The 60-minute backward gap threshold doesn't handle the
11:59PM→12:30AM edge case. When it's 11:59PM and the UI shows 12:30AM, `shutdownTime`
is constructed as today's 12:30AM (23h29m in the past), so `(now - shutdownTime)` is
~23.5h — not < 60 min — and the wrap does not fire. The sandbox would be incorrectly
reported as expired (-23h29m).

**Root cause:** The spec's "≤ 60 minutes" threshold was based on the assumption that the
midnight edge case involves a gap of ≤ 60 min. But the backward gap for 11:59PM→12:30AM
is 23.5 hours. The 60-min threshold correctly filtered the 2-hour-expired case but
incorrectly blocked the midnight case.

**Fix applied:**

Before:
```javascript
if (shutdownTime < now && (now.getTime() - shutdownTime.getTime()) < 60 * 60 * 1000) {
  shutdownTime.setDate(shutdownTime.getDate() + 1);
}
```

After:
```javascript
if (shutdownTime < now) {
  const minsUntilNextDay = Math.floor(
    (shutdownTime.getTime() + 24 * 60 * 60 * 1000 - now.getTime()) / 60000
  );
  if (minsUntilNextDay > 0 && minsUntilNextDay < 360) {
    shutdownTime.setDate(shutdownTime.getDate() + 1);
  }
}
```

The forward-looking 360-minute window correctly handles all cases:
- 4:02PM, expired 2:02PM: next-day 2:02PM = ~22h away → no wrap → reports -120 ✓
- 11:59PM, expires 12:30AM: next-day 12:30AM = 31 min away → wrap → reports +31 ✓
- 12:01AM, expired midnight: next-day midnight = ~23h59m away → no wrap → reports -1 ✓

**Process note:** Bug spec templates should specify "forward-looking threshold" as the
correct approach for midnight-wrap guards, not backward gap thresholds.

---

## Finding 2 — Bug doc Rules: "No other files touched" wording

**File:** `docs/bugs/2026-05-19-acg-extend-midnight-wrap-masks-expired-sandbox.md:84`

**What Copilot flagged:** "No other files touched" contradicts the repo convention that
CHANGELOG and memory-bank updates are required documentation.

**Fix:** Changed to "Code change limited to `playwright/acg_extend.js`; CHANGELOG and
memory-bank updates are required documentation."

---

## Finding 3 — Bug doc "Do NOT create a PR" in committed spec

**Files:** `docs/bugs/2026-05-19-acg-extend-midnight-wrap-masks-expired-sandbox.md:103`,
`docs/bugs/2026-05-19-acg-extend-sandbox-ttl-check.md:156`

**What Copilot flagged:** "Do NOT create a PR" is a Codex handoff guard and should not
appear in committed bug docs per the process rule added in PR #14 retro.

**Fix:** Removed "Do NOT create a PR" from both bug docs.

---

## Stale Findings (6) — resolved by main merge

Comments 3–6 flagged that `--check` mode and `acg_check_ttl()` did not exist in the
codebase. These were stale: the functions were shipped in PR #15 (merged to main as
`9c9b9b44`). Our merge commit (`0a167a9`) brought them into this branch.

Comment 9 about CHANGELOG describing CDP disconnect: the midnight-wrap entry was added
at line 9 (the new content); the CDP entries below were already in the file from the
`docs/next-improvements` base.

Comment 2 about the `finally` block CDP/persistent-context cleanup: pre-existing code
outside this PR's scope. Tracked for a follow-on fix.
