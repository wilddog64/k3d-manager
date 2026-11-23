# Bug: HoverFocus — hovering another window of the already-front app does not move focus

**Status:** OPEN
**Priority:** P2 (proposed) — degraded: cross-app hover works, same-app needs a click (the workaround)
**Introduced by:** `4cbd377` (hoverfocus M1a, variant B no-raise focus; documented known limitation)
**Should have been caught by:** spec (the probe skipped same-app targets; `docs/plans/hoverfocus-m1a-focus-core.md:33-35`)
**Introducing change reviewed:** yes (Fable)
**Waiting on:** dispatch
**Triage:** carry → hoverfocus v0.0.2 (operator, 2026-11-23: "ship v0.0.1 and fix bugs in v0.0.2")
**Prior art:** `docs/bugs/2026-11-23-hoverfocus-iterm-hollow-cursor-after-no-raise-focus.md` (filed same day, no score run) — read, related mechanism (key-window state), different symptom
**Filed:** 2026-11-23
**Detected by:** operator, E-L1 step 3 on m2-air (2026-11-23)

## Observed

Two TextEdit windows ("Untitled", "Untitled 2"). With "Untitled 2" key, hovering "Untitled" and typing: the text
went to "Untitled 2" ("test test"). Focus did not move between windows of the same app. Raise: n/a (nothing
changed).

## Cause (from the spec, not re-probed)

`hf_focus_without_raise` calls `_SLPSSetFrontProcessWithOptions(psn, wid, 0x400)` only. When the target process is
already front, that call does not change its key window. The M1a probe never tested same-app targets, and the spec
forbids adding the "make key" event records (variants C/D returned rc 1002). E-L1 step 3 was the planned live check
for this, and it confirms the limitation.

## Expected

Hovering a non-key window of the front app makes that window key, without raising it.

## Notes

- E-L1 steps 1-2 pass; step 3 records this limitation as the spec required. Operator 2026-11-23: does not block; ship v0.0.1, fix in v0.0.2.
- A fix needs a new probe (per "prove external behaviour before dispatch"), e.g. AX `kAXMainAttribute` /
  `kAXFocusedAttribute` set on the target window, checked for raise.
