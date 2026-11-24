# Bug: HoverFocus — terminals (iTerm2 and Terminal.app) show an unfocused cursor after hover focus returns to them

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-24, D3: "yes, and other command hotkeys") — Cmd-key shortcuts do not reach the hover-focused app until a click
**Introduced by:** `4cbd377` (hoverfocus M1a, no-raise focus via `_SLPSSetFrontProcessWithOptions`)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (Fable)
**Waiting on:** investigation — since 2026-11-23 (P1 probe)
**Triage:** carry → hoverfocus v0.0.3 (operator, 2026-11-24, D1: v0.0.2 = L1 + F1; deferred focus work moves to v0.0.3 batch L3)
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

## Recurrence — 2026-11-23: menu shortcuts (Cmd-W) do nothing in Safari after hover focus

Operator: after hovering Safari (it became the active app, TextEdit above it went inactive), "hotkey like cmd-w does
not apply to safari". Same root cause as the hollow cursor, now with a functional impact: the SkyLight call makes the
process frontmost, so plain keystrokes reach it, but no window of the app becomes key. Menu shortcuts like Close Tab
(Cmd-W), New Tab (Cmd-T) and Find (Cmd-F) act on the key window, so with none they are disabled and nothing happens.
B1 (same-app switch) is the same gap seen from the other side.

**Priority:** proposed P3 → P2 (degraded: menu shortcuts fail until you click; one click is the workaround). Operator
to confirm.

**To check (no code change):** after a hover, does Cmd-W close TextEdit's window, or Cmd-T open an iTerm tab? If not,
the symptom is general, not Safari's. The fix is the same P1 probe: make the target window key without raising it.

**Checked 2026-11-23 (operator):** TextEdit behaves the same, Cmd-W does nothing after hover focus. General, not
Safari's. Live test of any fix when the operator is home.
