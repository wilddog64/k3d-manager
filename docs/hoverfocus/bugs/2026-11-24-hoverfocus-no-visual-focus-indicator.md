# Bug: a window focused by hover shows no visual cue

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-24) — degraded: the user cannot tell which window will receive keys
**Triage:** HoverFocus v0.0.3 (operator, 2026-11-24: approved Claude's recommendation — v0.0.2 merges after L1/F1, this goes to v0.0.3)
**Introduced by:** pre-existing (inherent to focus-without-raise in M1a `4cbd377`)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (both)
**Waiting on:** dispatch — since 2026-11-24
**Prior art:** `docs/hoverfocus/bugs/2026-11-23-hoverfocus-iterm-hollow-cursor-after-no-raise-focus.md` (exact-slug
glob, read) — related: the app stays drawn as inactive, cursor shape is one instance; `make find-similar-docs` not run
**Filed:** 2026-11-24
**Detected by:** operator, 2026-11-24: "if focus on iTerm or any app, moving to textedit box behind it will not
highlight it so users won't know if they can edit on that app or not"

## Observed

Hovering TextEdit behind iTerm2 gives TextEdit key focus, but nothing changes on screen: TextEdit's title bar and
text view keep their inactive look, and iTerm2 still looks active.

## Why

The window is never raised and its app is never activated in the AppKit sense, so the app draws itself inactive. That
is the point of no-raise focus, so the cue has to come from HoverFocus itself.

## Candidate fixes (for the operator to choose)

1. HoverFocus draws a thin border overlay around the focused window (a borderless, click-through, non-activating
   `NSPanel` at the window's frame, tracked on focus change). Opt-out via config.
2. A brief flash or a menu-bar indicator showing the focused app's name (cheaper, weaker cue).
3. Document it as a known limitation only.
