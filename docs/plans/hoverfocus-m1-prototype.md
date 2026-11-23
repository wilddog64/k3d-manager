# hoverfocus M1 — focus follows mouse without raise (macOS), prototype: umbrella

**Status:** DRAFT rev 1, 2026-11-22 — Fable reviewed ("ready after fixes"); rev 2 pending. Repo created 2026-11-22 (public), interface commit `007879f` on `main` and `m1-base`; `main` protected (PR required, admins included, no force-push or delete, conversations resolved; CI check to be required once M1b adds CI)
**Tracked:** hoverfocus (OOB repo, like dirused), not a k3d-manager release; no `docs/ideas.md` row. Bugs go in
`docs/hoverfocus/bugs/`, ideas in `docs/hoverfocus/ideas.md`, specs in `docs/plans/hoverfocus-*.md`.
**Repo / branch:** `wilddog64/hoverfocus` (public; operator 2026-11-22) / base branch `m1-base`
(created by Claude from the interface commit below; the dispatcher refuses `main`)
**Version:** v0.1.0
**Risk:** low for the system (a user-space menu-bar app, user LaunchAgent, no sudo), medium for maintenance (private
SkyLight calls can break on any macOS update). Personal machines only (m4-air, m5-air); never a work machine.
**Children:** [`hoverfocus-m1a-focus-core.md`](hoverfocus-m1a-focus-core.md) (Luna: decision engine, config, private
API shim, event tap) and [`hoverfocus-m1b-app-shell.md`](hoverfocus-m1b-app-shell.md) (Flash: menu bar app, bundle,
install, CI, docs). They run in parallel against the fixed interface below.
**Filed:** 2026-11-22
**Spec reviewed:** pending (Fable; operator 2026-11-22: "be sure to have Fable review it before you dispatch out")
**Intent approved:** operator 2026-11-22 ("your intents approved"), for the evidence intent lines as written in rev 1; rev 2 keeps them verbatim
**Approval:** operator 2026-11-22 ("go ahead to write a spec but it should have its own repo, and track like
dirused"; "might be a good test to split task between two")

## Why

The operator wants focus follows mouse without raising the window, on the Macs they own. AutoRaise does this only in a
source build with `EXPERIMENTAL_FOCUS_FIRST` and `-delay 0`, with no tuning beyond two delays. Owning the tool gives
control over dwell timing, per-app rules, drag and menu handling, and a pause key.

## Facts this spec relies on

1. **Toolchain (Claude, m4-air, 2026-11-22):** Command Line Tools only (`/Library/Developer/CommandLineTools`),
   `Apple Swift version 6.3.3`, target `arm64-apple-macosx26.0`. A SwiftPM package with a test target fails with
   `error: no such module 'Testing'` and, with XCTest, `error: no such module 'XCTest'`. So tests are a plain
   executable target `hoverfocus-selftest` with its own assert helper, run by `swift run hoverfocus-selftest`. A
   SwiftPM package with a C target, three Swift targets and two executables builds (`swift build`, 34 s, clean).
2. **Private symbols (Claude, m4-air, macOS 26.5.2 build 25F84, 2026-11-22):** `dlopen` of
   `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` succeeds and `dlsym` finds
   `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`, `SLSMainConnectionID`,
   `SLSCopyWindowsWithOptionsAndTags`; ApplicationServices exports `GetProcessForPID` and `_AXUIElementGetWindow`.
   This proves the symbols exist, not that the call sequence focuses without raising; that is live evidence E-L1.
3. **Technique (public prior art, read for the method only, no code copied):** AutoRaise (`sbmpost/AutoRaise`, README
   `EXPERIMENTAL_FOCUS_FIRST`) and yabai (`focus_follows_mouse autofocus`) make a window key without ordering it front
   by calling `_SLPSSetFrontProcessWithOptions(&psn, wid, kCPSUserGenerated)` and then posting two synthetic event
   records with `SLPSPostEventRecordTo`. The exact byte layout of those records is the worker's to derive from public
   write-ups and to state in a comment with its source; copying source from either project is not allowed (their
   licences would attach). M1a must verify the sequence live (E-L1) before it is relied on.

## Design

```
CGEventTap (mouseMoved, listen-only)  →  PointerSample
AXUIElementCopyElementAtPosition      →  WindowTarget? (+ SystemState)
Engine.observe / Engine.tick          →  Decision (.none | .focus | .focusAndRaise)
Focuser (CSkyLight shim)              →  focus without raise, or NSRunningApplication.activate + AXRaise
```

- `HoverFocusCore`: pure Swift, Foundation only, no AppKit, no private API. All decision logic, fully testable.
- `CSkyLight`: the only C code; resolves private symbols with `dlsym` at runtime (never linked), reports the first
  missing symbol.
- `HoverFocusPlatform`: the only Swift that touches AX, CGEventTap or `CSkyLight`.
- `hoverfocus`: the app shell (menu bar, config file, permission prompt). Uses only the interface.
- `hoverfocus-selftest`: the test runner.

## Interface commit (Claude, before dispatch)

Claude creates the repo (after the operator's go), commits the package skeleton below to `main`, and branches
`m1-base` from it. Every file compiles today (verified in scratch, 2026-11-22). Neither worker edits `Package.swift`
or `Sources/HoverFocusCore/Interface.swift`; a change to either is a spec change, raised to Claude.

| File | Owner after the interface commit |
|---|---|
| `Package.swift` | Claude (fixed) |
| `Sources/HoverFocusCore/Interface.swift` | Claude (fixed) |
| `Sources/HoverFocusCore/Engine.swift`, `ConfigLoader.swift` | M1a (stubs replaced) |
| `Sources/CSkyLight/**` | M1a |
| `Sources/HoverFocusPlatform/**` | M1a |
| `Sources/hoverfocus-selftest/**` | M1a |
| `Sources/hoverfocus/**` | M1b |
| `Makefile`, `packaging/**`, `tests/**`, `.github/**`, `README.md`, `docs/**`, `config.example.json` | M1b |

Public names the shell may use (M1b) and M1a must keep: `Config`, `PauseModifier`, `ConfigError`,
`ConfigLoader.load(from:)`, `ControllerError`, `FocusControlling`, `HoverFocusController(config:)`,
`AccessibilityPermission.isTrusted(prompt:)`. The full text of `Interface.swift` is in the interface commit; summary:

- `Config` (Codable): `enabled` (true), `dwellMs` (150), `stillnessPx` (4), `ignoreWhenButtonDown` (true),
  `pauseModifier` (`function`), `ignoreApps` ([] bundle ids), `raiseApps` ([] bundle ids).
- `FocusDeciding`: `observe(_:under:state:) -> Decision`, `tick(nowMs:state:) -> Decision`.
- `FocusControlling`: `isRunning`, `isPaused`, `start() throws`, `stop()`, `apply(_:)`.
- `ControllerError`: `accessibilityNotTrusted`, `privateAPIUnavailable(symbol:)`, `eventTapFailed`.

Config file: `~/.config/hoverfocus/config.json`. A missing file means defaults.

## Landing

Each child lands on `m1-base` through the dispatcher (`--repo ~/src/gitrepo/personal/hoverfocus --branch m1-base`).
The file split means no overlap. After both land and E-L1 to E-L4 pass, Claude opens `m1-base` → `main` as PR v0.1.0,
reviewed blind by Argon (no Copilot on OOB repos), merged by the operator.

## Live evidence (operator at the Mac, Claude reading; after both children land)

- E-L1: hover from a front window onto a partly covered window and type: keystrokes go to the hovered window, and its
  stacking order is unchanged (screenshot before and after).
- E-L2: drag a file across windows: no focus change during the drag.
- E-L3: hold the pause modifier, or open a menu: no focus change.
- E-L4: an app in `raiseApps` is focused and raised; an app in `ignoreApps` is never focused.

## The split as a trial

This is the first parallel Luna + Flash dispatch on one feature. Record per child: resumes, land refusals, verify
result, and whether the interface held (any request to change `Interface.swift` counts as a miss). Note it in
`project_complex_bug_decomposition_trial` memory at the end.
