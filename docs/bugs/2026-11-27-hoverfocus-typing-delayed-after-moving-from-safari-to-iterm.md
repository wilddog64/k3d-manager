# Bug: after hovering from Safari to iTerm, the first keystrokes are delayed or go to Safari

**Status:** OPEN — captured, not triaged
**Priority:** P3 (proposed; Argon classifies)
**Introduced by:** unknown
**Should have been caught by:** unknown
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Filed:** 2026-11-27, Claude, from operator report (HoverFocus v0.0.3 branch `a4244b6`)
**Component:** `hoverfocus` `Sources/HoverFocusCore/Engine.swift` (dwell :78), `Controller.swift` `applyDecision` :322
(`enableAccessibilityTree`, `hf_focus_without_raise`)

## Report (operator, 2026-11-27)

"sometime HoverFocus delay the text input if focus on Safari and move cursor back to iTerm". Intermittent.

## What is known

- Focus changes only after the pointer has been still for `dwellMs` (default 150 ms, `docs/config.md:12`); keys typed
  before that go to the previous window by design.
- Each decision calls `enableAccessibilityTree(pid:)` and then the private no-raise focus call; either could stall when
  the previous app is Safari (a large accessibility tree).
- Not yet known: whether the keys are late (arrive in iTerm after a pause) or misrouted (land in Safari), and how long
  the pause is. Capture: `log stream --predicate 'subsystem CONTAINS "hoverfocus"'` while reproducing, plus whether it
  happens with `dwellMs` 0.
