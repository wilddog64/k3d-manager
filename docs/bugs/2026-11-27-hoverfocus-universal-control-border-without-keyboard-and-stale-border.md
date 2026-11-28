# Bug: HoverFocus under Universal Control draws the focus border on the second Mac but keys do not follow, and the border stays after the cursor leaves

**Status:** OPEN — captured, not triaged
**Priority:** P3 (proposed; Argon classifies)
**Introduced by:** pre-existing (cross-Mac use never designed for)
**Should have been caught by:** none
**Introducing change reviewed:** unknown
**Waiting on:** investigation — since 2026-11-28 (Fable + Neon blind review; then intents for operator approval)
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Filed:** 2026-11-27, Claude, from operator report (HoverFocus v0.0.3 branch `a4244b6`, installed on m4 and m2)
**Component:** `hoverfocus` `Sources/HoverFocusPlatform/Controller.swift` (`handle` :141, `applyDecision` :322, indicator)

## Report (operator, 2026-11-27)

m2 and m4 share one keyboard and pointer through Apple Universal Control. Moving the cursor from m2 onto m4: HoverFocus
on m4 turns the hovered window's border blue, but typed text does not arrive there. Moving the cursor back to m2: the
blue border on m4 stays.

## What is known

- HoverFocus on m4 receives the pointer events (the border is drawn, so the tap saw `mouseMoved` and the engine
  decided). Pointer position comes only from tapped events (`lastPointer = event.location`, `Controller.swift:148`).
- Default focus path is `hf_focus_without_raise` (no app activation); the raise path sets `kAXFrontmostAttribute`.
- Not yet known: whether the keys stay on m2 (Universal Control keeps the keyboard on the Mac that last had a click)
  or are lost on m4 (activation did not take). Operator test: with the border showing and no click, type and see where
  the letters go.
- **Local control (operator screenshot, m4, 2026-11-27 18:52):** with m4's own keyboard and trackpad, hovering iTerm
  behind BetterTouchTool gives iTerm the blue border and typed text lands in iTerm while BetterTouchTool stays on top.
  Focus-without-raise works on m4, so the cross-Mac failure is not an m4 install, grant or focus-call problem; the
  leading explanation is that Universal Control keeps the keyboard on m2 until a click on m4 (still to confirm).
- Stale border: after the cursor leaves m4, m4's HoverFocus gets no more events, so the indicator keeps its last state.

## Possible directions (for triage, not a spec)

- Hide or dim the indicator when no pointer event has arrived for N seconds and the last pointer was at a display edge.
- If keys stay on m2: document as a Universal Control limit (hover cannot move the keyboard between Macs).

## Update — 2026-11-27 20:30 PST (after C1 `6bd845c`, signed build on m4)

Operator: crossing from m2 to m4, HoverFocus focuses the hovered m4 window ("it does have focus"), but typed text does
not arrive. Together with the m4-local control (keys reach a hover-focused, unraised window when m4's own keyboard is
used), this points to Universal Control keeping keyboard input on m2 until a click on m4. HoverFocus cannot move the
keyboard between Macs (no public API; a synthetic click would click into the window). Proposed resolution for triage:
document as a limitation with the workaround "click once after crossing"; keep the stale-border half as the fixable
part (hide the border when the pointer leaves the screen).

## Update — 2026-11-28 (operator report on m4; return trip)

Operator: "move cursor from m2 to m4 the iTerm window border will turn blue but not able to type. click the m4 iTerm2
and move cursor back to m2 iterm, m4 iterm blue line will not go away, and can't type on m2 iterm until I click it".

New: the **return trip** has the same shape. After a click on m4, moving back onto m2's iTerm2 does not bring typing
back to m2 without a click. On m2, `Engine.observe` returns no action when the hovered window already equals
`state.focusedWindowID` (hoverfocus `Sources/HoverFocusCore/Engine.swift:61`, v0.0.3 `6bd845c`); m2's iTerm2 was never
unfocused locally, so HoverFocus has nothing to do, consistent with Universal Control holding the keyboard on m4 until a
click on m2. The decisive capture is still open: with HoverFocus **quit on both Macs**, does typing follow the pointer
without a click? (A duplicate doc filed in the hoverfocus repo on 2026-11-28 was removed in favour of this one.)

## Blind reviews — 2026-11-28 (Fable; Neon `gemini-4-neon-high`, brief `docs/plans/review-hoverfocus-universal-control.md`)

**Priority:** Fable P3 (conditional); Neon P2 now, P3 once capture 1 rules HoverFocus out. Both: P2 if, with HoverFocus
quit on both Macs, typing follows the pointer without a click (then the suspect is the SkyLight focus sequence,
`Sources/CSkyLight/CSkyLight.c:79-97`).

Agreed findings:
- HoverFocus cannot touch keystrokes: the event tap is `.listenOnly` and mouse-only (`Controller.swift:69-73`, `:99-105`).
- `Engine.swift:61` is right for the return trip but is not the cause; a second gate, `firedWindow`
  (`Engine.swift:54-56`, `:65`, `:92`), blocks the same case. Re-firing would not help: on m4 the focus call succeeded
  and the window had focus, yet keys did not arrive.
- The stale border is designed behaviour, not "no more events": `onTick` keeps polling every 250 ms
  (`TickPolicy.swift:6`) and `observeFocused` sees focused == tracked (`FocusIndicator.swift:47-48`). It also stays on
  one Mac when the pointer goes to the desktop. Side cost: a 4 Hz CGWindowList + AX loop while the user is on the
  other Mac.
- Clicking the tracked window does not clear the border (`FocusIndicator.swift:37-42`, asserted in the selftest).
- No proven "pointer left this Mac" signal: Quartz may clamp the cursor to the edge; `CGCursorIsVisible` is unsafe
  (hidden while typing); edge + idle heuristics hide the border for someone parked at an edge, and must ignore seams
  between local displays. Needs a probe before a spec.
- Diagnostics: only `ax-enable` and `focus failed` are logged; no decision/skip lines.
- Keyboard: no public API; any synthetic click (title bar, desktop, content) is unproven to move Universal Control's
  keyboard and risks raising, tab hits, zoom or drags. Recommended: document the limitation.
- Disagreement to settle in the spec: Fable says **suppress** the border (a reset never redraws on return to the same
  still-focused window, since the Engine returns `.none`); Neon says **reset** (so the 4 Hz tick stops). Both goals hold
  with a suspended state: hide and stop polling while away, redraw on the next pointer event over the tracked window.
- Captures to add: keys land where (visible prompt on both Macs), both directions, with TextEdit as well as iTerm2;
  `lsappinfo front` on each Mac during the excursion; the physical keyboard used; macOS versions; whether
  BetterTouchTool or other taps run; border duration over 1 s.
