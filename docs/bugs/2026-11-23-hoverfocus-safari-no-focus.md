# Bug: HoverFocus does not focus Safari windows

**Status:** OPEN
**Priority:** P2 (proposed) — degraded: Safari windows must be clicked to focus
**Introduced by:** `4cbd377` (M1a focus core: `Controller.swift` `lookup(x:y:)`)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (both)
**Waiting on:** investigation
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

## Next

1. Operator quick check: hover over an unfocused Safari window's tab bar, then over its page.
2. Probe (with P1 on m2, ~15:30): log the parent-walk depth to reach `AXWindow` over page content, and whether
   `kAXWindowAttribute` on the hit element returns the window directly.
3. Candidate fix (L2, `Controller.swift`): read `kAXWindowAttribute` first, falling back to the parent walk; or take the
   window id from `CGWindowListCopyWindowInfo` at the point (layer 0, frontmost) and keep AX only for raise.
