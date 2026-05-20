# Retrospective — PR #16: midnight-wrap guard fix

**Date:** 2026-05-20
**Milestone:** fix/acg-extend-midnight-wrap
**PR:** #16 — merged to main (`04ffd365`)
**Participants:** Claude, Codex, Copilot

## What Went Well
- Fix is clean and correct: forward-looking 360-min threshold handles all three cases
- CI green on first pass
- Copilot caught a real logic bug (inverted midnight-wrap condition) that the spec's reasoning had wrong
- All 9 Copilot threads resolved cleanly

## What Went Wrong
- Branch diverged from main: was created from `docs/next-improvements` (pre-PR #15 merge), causing CHANGELOG and memory-bank conflicts
- Haiku subagent (Phase 1 /create-pr) modified CHANGELOG.md locally but did not commit or push — caused dirty PR state
- PR was `dirty` (mergeable_state: dirty) immediately after creation due to CHANGELOG conflict with main
- Original spec's 60-min backward gap reasoning was incorrect for the 11:59PM→12:30AM edge case — Copilot caught this; correct fix uses forward-looking window
- Codex did not push the branch after committing (known failure mode)

## Process Rules Added

| Rule | File | Reason |
|------|------|--------|
| Always create fix branches from `main`, not `docs/next-improvements` | — | Prevents divergence/conflict on CHANGELOG and memory-bank |
| Use forward-looking threshold for midnight-wrap guards, not backward gap | bug spec template | Backward gap for 11:59PM→12:30AM is 23.5h, not ≤ 60 min |
| "Do NOT create a PR" must not appear in committed bug docs | docs/bugs/ convention | Handoff guard, not a workflow rule |
| Rules section: "Code change limited to X; CHANGELOG and memory-bank updates are required" | bug spec template | Clearer than "No other files touched" |

## Decisions Made
- 360-minute forward-looking window chosen for midnight-wrap: covers near-midnight cases (< 6h remaining) while treating all other expired sandboxes correctly
- CDP `finally` block issue (comment 2) deferred to a follow-on fix — out of scope for this PR

## Theme
A one-line fix to the midnight-wrap guard grew into a branch conflict cleanup, a CHANGELOG merge, and a Copilot-caught logic inversion. The spec's reasoning about "60-minute gap" was correct in intent but wrong in implementation — backward gap for the 11:59PM edge case is 23.5 hours, not 60 minutes. Copilot caught this, Claude fixed it with a forward-looking threshold. Clean merge, all threads resolved.
