# Bug: HoverFocus — terminals (iTerm2 and Terminal.app) show an unfocused cursor after hover focus returns to them

**Status:** OPEN
**Priority:** P3 — cosmetic; keystrokes reach iTerm, one click restores the solid cursor
**Introduced by:** `4cbd377` (hoverfocus M1a, no-raise focus via `_SLPSSetFrontProcessWithOptions`)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (Fable)
**Waiting on:** dispatch
**Triage:** carry → hoverfocus v0.0.2 (operator, 2026-11-23: "ship v0.0.1 and fix bugs in v0.0.2")
**Prior art:** none above threshold (no earlier hoverfocus bug docs)
**Filed:** 2026-11-23
**Detected by:** operator, E-L1 on m2-air (2026-11-23), build at pid 578

## Observed

E-L1 step 1 passed: hovering a TextEdit window behind iTerm2 sent typing to TextEdit without raising it. When the
pointer moved back over iTerm2, typing went to iTerm2, but its cursor was drawn hollow (iTerm2's "window not key"
style). One click in iTerm2 made it solid again. Terminal.app behaves the same (operator, 2026-11-23: typed
"hello from terminal" into TextEdit, then back over Terminal the input went to Terminal with an unfocused cursor),
so this is not iTerm2-specific.

## Likely cause (unproven)

`Controller.applyDecision` focuses without raising through `hf_focus_without_raise` (SkyLight front-process call). It
makes the process frontmost for input but the terminal apps do not appear to receive the key-window change it redraws its
cursor from. Needs a capture of the app's key-window state (AX `AXFocusedWindow`/`AXMain`) before and after a hover.

## Expected

After hover focus, the app's window looks active (solid cursor) as well as receiving keystrokes.

## Next

- Terminal.app tested 2026-11-23: same. Check whether TextEdit's own focus ring/caret shows the same lag.
- Not an M1 blocker (operator, 2026-11-23).
