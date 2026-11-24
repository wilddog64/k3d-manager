# Bug: HoverFocus does not focus Safari windows

**Status:** OPEN
**Priority:** P2 (proposed) — degraded: Safari windows must be clicked to focus
**Introduced by:** `4cbd377` (M1a focus core: `Controller.swift` `lookup(x:y:)`)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (both)
**Waiting on:** investigation — P1 app matrix on m2
**Prior art:** not run (find-similar-docs vector store unavailable; exact-slug glob found nothing)
**Filed:** 2026-11-23
**Detected by:** operator, 2026-11-23 ("hoverfocus does not work for Safari")

## Observed

Hovering over an unfocused Safari window does not focus it. Other apps work.

## Suspected cause (from code reading, not yet proven live)

`Controller.swift` `lookup(x:y:)` calls `AXUIElementCopyElementAtPosition`, then walks `kAXParentAttribute` at most
**8 levels** looking for `AXWindow`. A web page's accessibility tree (`AXWebArea` and the groups, links and text
inside it) is usually deeper than 8 levels. If the walk stops before the window, `hf_ax_window_id` fails, `lookup`
returns nil and the engine never gets a target. The 0.2 s AX messaging timeout on web content (served by Safari's
WebContent process) is a second suspect. Safari's design is not the obvious cause: Safari exposes a full AX tree and
standard windows.

**Prediction to check:** focus works over Safari's tab bar or toolbar (shallow tree) but not over page content.

## Update 2026-11-23 (operator screenshot)

Operator: "works". The screenshot shows Safari (YouTube, video area) key with a TextEdit window above it whose title
bar is inactive, so a hover reached Safari without a click and without raising. So Safari is not refused outright.
Still open: which point was hovered (video area vs text or links), and whether the earlier failure depends on where
the pointer sits (deep tree under text/links) or was a one-off. If it does not come back over text and links, close as
not reproducible.

## Update 2026-11-24 — second symptom: Safari raised itself

On m2 (macOS 26, fresh `make install` of v0.0.1 plus README, agent running, no log errors), hovering a Safari window
(YouTube, behind iTerm2) brought Safari **to the front** and opened the address-bar Favorites list. Control in the same
session: TextEdit behind iTerm2 got hover focus and stayed behind, so variant B (`kCPSNoWindows`) still works and the
raise comes from Safari. That differs from the 2026-11-23 screenshot (Safari focused under TextEdit, not raised).

Hypothesis (unproven): when Safari's first responder is the address field (new-tab page, or a field focused earlier),
its activation path orders the window front and shows Favorites; over plain page content it does not. Workaround for
now: `"ignoreApps": ["com.apple.Safari"]`.

Three Safari behaviours are now in play: no focus at all (first report), focus without raise (11-23), focus with raise
(11-24). The P1 app matrix in [`hoverfocus-v0.0.2-bug-batches.md`](../../plans/hoverfocus-v0.0.2-bug-batches.md) records
which Safari state gives which.

## P1 app matrix — 2026-11-24 (operator, m2, macOS 26.5.1)

Build: m1-base `dc68692` installed 17:34 (L1/F1 not yet installed; neither touches `Controller.swift`, so the focus
results stand). Each window behind iTerm2, pointer resting on it; operator report, verbatim where quoted.

| App | Focused | Notes |
|---|---|---|
| Safari | yes | Cmd+L and Cmd+T reach Safari; typed text reached the page ("testdsasfdasdf"); **Cmd+W did not close the tab** |
| Finder | yes | Cmd+G works |
| TextEdit | yes | control |
| MacVim | yes | |
| Slack | **no** | "does not receive focus when under iTerm" |
| VS Code | **no** | "not working" |
| Chrome, Mail, Terminal.app | not run | |

Raise was not reported for any app this run (the 11-24 Safari raise did not recur). Findings:
- Safari focus works over page content on this build, so the original "no focus" symptom did not reproduce; Cmd+W is the
  open Safari gap (a window-level command; hypothesis: routed to the key window of the frontmost app, not Safari).
- Both Electron apps fail: filed separately as
  [`2026-11-24-hoverfocus-electron-apps-no-focus.md`](2026-11-24-hoverfocus-electron-apps-no-focus.md).
- No visual cue on the focused window: filed as
  [`2026-11-24-hoverfocus-no-visual-focus-indicator.md`](2026-11-24-hoverfocus-no-visual-focus-indicator.md).

## Next

1. Operator quick check: hover over an unfocused Safari window's tab bar, then over its page.
2. Probe (with P1 on m2, ~15:30): log the parent-walk depth to reach `AXWindow` over page content, and whether
   `kAXWindowAttribute` on the hit element returns the window directly.
3. Candidate fix (L2, `Controller.swift`): read `kAXWindowAttribute` first, falling back to the parent walk; or take the
   window id from `CGWindowListCopyWindowInfo` at the point (layer 0, frontmost) and keep AX only for raise.
