# Bug: HoverFocus does not focus Electron apps (Slack, VS Code)

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-24) — degraded: Electron windows must be clicked to focus
**Triage:** HoverFocus v0.0.3 (operator, 2026-11-24: approved Claude's recommendation — v0.0.2 merges after L1/F1, this goes to v0.0.3)
**Introduced by:** `4cbd377` (M1a focus core, variant B no-raise focus)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (both)
**Waiting on:** dispatch — since 2026-11-24
**Prior art:** `docs/hoverfocus/bugs/2026-11-23-hoverfocus-safari-no-focus.md` (exact-slug glob, read) — same no-focus
class, different apps; `make find-similar-docs` not run
**Filed:** 2026-11-24
**Detected by:** operator, 2026-11-24, P1 app matrix on m2 (macOS 26.5.1): "slack does not receive focus when under
iTerm", "vscode behind iTerm: not working"

## Observed

With Slack or VS Code behind iTerm2 and the pointer resting on it, keys still go to iTerm2. TextEdit, MacVim, Finder
and Safari focus in the same session, so the agent is running and trusted.

## Suspected cause (unproven)

Electron (Chromium) windows may take key focus only through a real app activation, ignoring the SkyLight
`kCPSNoWindows` front-process switch plus the key-window event that variant B sends. Probe for L2: log whether the
AX lookup finds the Electron `AXWindow` at all (Chromium exposes AX lazily, often only after
`AXManualAccessibility`/`AXEnhancedUserInterface` is set), before blaming the focus call.

## Workaround

Click the window. Adding the apps to `ignoreApps` changes nothing (they already do not focus).
