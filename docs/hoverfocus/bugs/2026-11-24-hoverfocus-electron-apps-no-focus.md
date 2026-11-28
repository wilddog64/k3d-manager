# Bug: HoverFocus does not focus Electron apps (Slack, VS Code)

**Status:** LIVE-VERIFIED — L3 `3951b67` (AXManualAccessibility + variant Y) and L4 `11e0e7c` (window resolved via AXWindow) on hoverfocus `v0.0.3`; operator on m2 2026-11-25: Slack message area and VS Code editor text take focus without raise
**Priority:** P2 (operator, 2026-11-24) — degraded: Electron windows must be clicked to focus
**Triage:** HoverFocus v0.0.3 (operator, 2026-11-24: approved Claude's recommendation — v0.0.2 merges after L1/F1, this goes to v0.0.3)
**Introduced by:** `4cbd377` (M1a focus core, variant B no-raise focus)
**Should have been caught by:** live check
**Introducing change reviewed:** yes (both)
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

## Recurrence — v0.0.3 live check (2026-11-25, m2, macOS 26.5.1 25F80)

L3 (`3951b67`, AXManualAccessibility once per pid + variant Y focus) landed on hoverfocus `v0.0.3`; the operator's live
check at m2 (install `7b42f63`, signed with the local identity): **Slack content does not take focus; hovering Slack's
three window buttons does, and typing then lands in the DM.** Chrome, Safari, TextEdit (both windows) and Terminal pass.

HoverFocus log (`log stream`, subsystem `com.wilddog64.hoverfocus`, 19:20–19:23): `ax-enable` for TextEdit pid 98410
and Chrome pid 54051 (rc -25205), none for Slack pid 76191 in the window, no `focus failed`. The focus call never ran.

Probe `~/hf-probe/hf-p4-lookup.swift` (read-only replay of `Controller.lookup`, operator at m2's keyboard, 2026-11-25):

| Pointer on | AXWindow depth | 8-level walk stops at | window id from stop element | AXWindow attribute on hit |
|---|---|---|---|---|
| iTerm2 text | 4 | AXWindow | rc 0, 269245 | rc 0, 269245 |
| Slack DM content | 20 (`AXGroup > … > AXWebArea > AXScrollArea > …`) | **AXGroup** | rc 0, 280187 (correct) | rc 0, 280187 |
| Slack window button | 1 (`AXButton > AXWindow`) | AXWindow | rc 0, 280187 | rc 0, 280187 |

`ElementAtPosition` succeeded in 0–33 ms at both 0.2 s and 2.0 s timeouts, so the timeout is not the cause.

### Root cause (proven)

`Controller.lookup` (`Sources/HoverFocusPlatform/Controller.swift`, from `4cbd377`) climbs at most 8 parents looking
for the `AXWindow`, then reads `kAXSubroleAttribute` **from wherever the climb stopped**. For Slack content it stops at
an `AXGroup`; `_AXUIElementGetWindow` still returns the right window id, but the subrole is not `AXStandardWindow`, so
the target carries `isStandardWindow: false` and `Engine.permitted` (`Sources/HoverFocusCore/Engine.swift:26`) refuses
it silently. The window buttons are depth 1, so the climb reaches the window and focus works, matching the operator's
observation. The earlier P2 probe passed Slack because it took window ids from `CGWindowListCopyWindowInfo`, never from
this lookup; L3's spec did not cover the lookup.

### Fix direction

Resolve the window element from the hit with `kAXWindowAttribute` (probe: rc 0, correct id for all three spots); fall
back to the parent climb only if that fails; read the subrole and window id from the resolved window element.

