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
