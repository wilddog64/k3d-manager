# hoverfocus v0.0.3 U2 — border overlay on the hover-focused window (D2)

**Status:** spec rev 1 — reviews pending (Fable + Neon, independent); not dispatched
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.3-plan.md`](hoverfocus-v0.0.3-plan.md) (batch U2, decision D2 option 1)
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.3` at `2e30655` (L3 `3951b67`, U1 `4e66919`, F2 `7b42f63`, L4 `11e0e7c`)
**Risk:** medium (new on-screen window owned by HoverFocus; must never take focus, clicks or activation)
**Implementer:** Flash (`agy`, `gemini-3.8-flash-medium`). **Verifier:** Claude, from `## Acceptance` only.
**Filed:** 2026-11-26
**Approval:** operator 2026-11-26 ("let's execute (a). so go ahead to spec out U2 and have Fable/Neon review then dispatch to Flash")

## Fixes

| Input | Defect (v0.0.3 `2e30655`) |
|---|---|
| `docs/hoverfocus/bugs/2026-11-24-hoverfocus-no-visual-focus-indicator.md` (P2) | A window focused by hover keeps its inactive look (its app is never activated, by design of no-raise focus), so the user cannot tell which window will receive keys. D2 (operator, 2026-11-24): option 1, a thin click-through border overlay around the focused window, opt-out `focusIndicator: false`. |

## External behaviour (proof, before dispatch)

Probe `order.swift`, Claude, m4-air macOS 26.5.2, 2026-11-26, run in the operator's console session with two Finder
windows open (layer 0, front to back): an `NSPanel` with `styleMask [.borderless, .nonactivatingPanel]`,
`isOpaque = false`, `backgroundColor = .clear`, `ignoresMouseEvents = true`, `hasShadow = false`, `level = .normal`,
`collectionBehavior [.canJoinAllSpaces, .transient, .ignoresCycle]`, then `order(.above, relativeTo: <2nd window's
CGWindowID>)`. Read back with `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`:

```
target: 2nd window, id 11571, owner Finder
panel #11573 index 13, target index 14
panel directly above target: true
front window still in front of panel: true
frontmost app unchanged: true (com.apple.finder)
isKeyWindow false canBecomeKey false
```

So a panel owned by HoverFocus can sit directly above another process's window in the stacking order: windows in front
of the target also cover its border, and the panel never becomes key or activates HoverFocus. `NSWindow.windowNumber`
equals the CGWindowID used in the window list. `.canJoinAllSpaces` was in the probe; the spec drops it (see Behaviour 3),
which does not affect ordering.

Coordinates: `kCGWindowBounds` is in global display space with the origin at the top-left of the primary display, y
down; AppKit frames have the origin at the bottom-left of the primary display, y up. Conversion:
`cocoaY = primaryHeight - (cgY + height)`, `primaryHeight = NSScreen.screens.first!.frame.height` (the primary display is
always `screens[0]`).

## Before You Start

1. `git -C <hoverfocus> log --oneline -1` shows `2e30655`. Read `Sources/HoverFocusPlatform/Controller.swift` (whole),
   `Sources/HoverFocusCore/Interface.swift` (`Config`, `Decision`), `Sources/HoverFocusCore/ConfigLoader.swift`, and the
   config rows in `Sources/hoverfocus-selftest/main.swift:120-164`.
2. `make build` and `make selftest` pass before any edit (record the passed count; 104 `check(` call sites today).
3. No change outside `## Files`. No private API, no new entitlement, no change to focus behaviour.

## Behaviour

### 1. Config: `focusIndicator` (default `true`)

- `Config` gains `public var focusIndicator: Bool`, init parameter `focusIndicator: Bool = true` (last parameter).
- `ConfigLoader`: add `"focusIndicator"` to `knownKeys` and `try readBoolean("focusIndicator") { config.focusIndicator = $0 }`.
  A non-boolean is rejected with reason `focusIndicator must be boolean`.
- Contract: `AppDelegate` writes `JSONEncoder().encode(Config())` as the default config and the selftest round-trips an
  encoded `Config`; both now carry `focusIndicator`, so the loader must accept it in the same change.

### 2. Pure model: `Sources/HoverFocusCore/FocusIndicator.swift` (new)

```swift
public struct IndicatorRect: Sendable, Equatable { public var x, y, width, height: Double }

public struct FocusIndicatorModel: Sendable, Equatable {
    public private(set) var trackedWindowID: UInt32?
    public init()
    public mutating func decided(_ decision: Decision, succeeded: Bool)
    public mutating func mouseDown(onWindow windowID: UInt32?)
    public mutating func reset()
    public func frame(enabled: Bool, paused: Bool, bounds: (UInt32) -> IndicatorRect?, primaryHeight: Double,
                      outset: Double) -> IndicatorRect?
}

public enum IndicatorGeometry {
    public static func cocoaFrame(cgBounds: IndicatorRect, primaryHeight: Double, outset: Double) -> IndicatorRect
}
```

- `decided`: `.focus(t)` with `succeeded` → track `t.windowID`; `.focus` not succeeded → clear; `.focusAndRaise` → clear
  (the app is activated and draws itself active, so no border); `.none` → unchanged.
- `mouseDown(onWindow:)`: a click on any window other than the tracked one (including `nil`, unknown) clears it; a click
  on the tracked window keeps it.
- `reset()`: clears (stop, trust loss, pause).
- `frame`: `nil` when `!enabled`, `paused`, nothing tracked, or `bounds(id)` is `nil` (window closed, minimized, hidden or
  off the current Space); otherwise `IndicatorGeometry.cocoaFrame(...)` of those bounds.
- `cocoaFrame`: `x - outset`, `primaryHeight - (y + height) - outset`, `width + 2*outset`, `height + 2*outset`.

### 3. Platform panel: `Sources/HoverFocusPlatform/FocusIndicatorPanel.swift` (new)

`@MainActor final class FocusIndicatorPanel` owning one `NSPanel`, created lazily on first `show`, configured exactly as
in the probe except `collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]` (no `.canJoinAllSpaces`:
the border must not appear on another Space). Its content view draws only a rounded-rectangle stroke: line width 3,
corner radius 12, inset by half the line width, colour `NSColor.controlAccentColor`; the interior stays clear.

- `show(frame: NSRect, aboveWindow id: UInt32)`: `setFrame(frame, display: true)` then
  `order(.above, relativeTo: Int(id))`. Never `makeKey`, `makeKeyAndOrderFront`, `orderFrontRegardless` or
  `NSApp.activate`.
- `hide()`: `orderOut(nil)` if visible.

### 4. Controller hooks (`Sources/HoverFocusPlatform/Controller.swift`)

- Properties: `private var indicator = FocusIndicatorModel()`, `private let indicatorPanel = FocusIndicatorPanel()`,
  `private var indicatorEnabled: Bool` (from config in `init` and `apply`).
- `applyDecision`: after computing `result`, call `indicator.decided(decision, succeeded: result == 0)` (only for
  `.focus`/`.focusAndRaise`; `.none` returns early as today).
- `handle`: on `.leftMouseDown`, `.rightMouseDown` or `.otherMouseDown`, call
  `indicator.mouseDown(onWindow: target?.windowID)` before `engine.observe`.
- `onTick`: when `isPaused`, `indicator.reset()` and `indicatorPanel.hide()` before the existing early return.
  Otherwise, after `applyDecision`, compute `indicator.frame(enabled: indicatorEnabled, paused: false, bounds: <live>,
  primaryHeight: <primary screen height>, outset: 2)`; `nil` → `hide()`, else `show(frame:aboveWindow:)` with the tracked
  ID. `<live>` reads `CGWindowListCopyWindowInfo([.optionIncludingWindow], id)` and returns the bounds only when
  `kCGWindowIsOnscreen` is true and alpha > 0; this runs at the existing 50 ms tick, so the border follows moves and
  resizes within one tick.
- `stop()`: `indicator.reset()`, `indicatorPanel.hide()`.
- `apply(_:)`: update `indicatorEnabled`; when it turns false, `hide()` on the next tick (the model already returns nil).

### 5. Docs

- `docs/config.md`: a `focusIndicator` row (Boolean, `true`, "Draws a thin accent-colour border around the window
  focused by hover; set false to turn it off.") in alphabetical order.
- `config.example.json`: `"focusIndicator" : true` in sorted-key position.
- `README.md` § Known Limitations: one line — the border is drawn by HoverFocus, so the focused app itself still looks
  inactive (title bar, cursor shape).

## Files

| File | Change |
|---|---|
| `Sources/HoverFocusCore/FocusIndicator.swift` | new: `IndicatorRect`, `FocusIndicatorModel`, `IndicatorGeometry` |
| `Sources/HoverFocusPlatform/FocusIndicatorPanel.swift` | new |
| `Sources/HoverFocusPlatform/Controller.swift` | hooks in Behaviour 4 only |
| `Sources/HoverFocusCore/Interface.swift` | `Config.focusIndicator` |
| `Sources/HoverFocusCore/ConfigLoader.swift` | known key + boolean read |
| `Sources/hoverfocus-selftest/main.swift` | rows in Acceptance |
| `docs/config.md`, `config.example.json`, `README.md` | Behaviour 5 |

## Contract readers

- `Config` (new field): readers `ConfigLoader.load` (`ConfigLoader.swift:27-86`), `AppCoordinator` (`apply`, `:36`, `:60`),
  `Controller.init`/`apply`; writers `AppDelegate.swift:283-286` (default config file) and the selftest round trip
  (`main.swift:160-164`). A config containing `focusIndicator` is rejected as "unknown key" by v0.0.2 and earlier
  binaries (downgrade only; note in the release notes).
- No change to `Decision`, `Engine`, `WindowResolver`, `hf_focus_without_raise` or the event mask.

## What NOT to Do

- No change to which window gets focus or when; the indicator only observes decisions.
- The panel never becomes key or main, never activates HoverFocus, never receives mouse events, never uses
  `.canJoinAllSpaces` or a level above `.normal`.
- No animation, no fade, no per-app colour, no menu item (config only, per D2).
- No `CGWindowListCopyWindowInfo` call outside the 50 ms tick (not in the event tap callback).

## Acceptance

```yaml
must:
  - id: M1
    text: "After a successful hover focus (.focus), the model tracks that window and frame() returns its Cocoa frame outset by 2: for primaryHeight 1000 and CG bounds (100, 50, 400, 300), the frame is (98, 648, 404, 304)"
  - id: M2
    text: "The model follows the latest decision: a second successful .focus of another window moves tracking to it"
  - id: M3
    text: "focusIndicator parses: default true when absent; true and false accepted; a non-boolean rejected with 'focusIndicator must be boolean'; an encoded Config() round-trips through ConfigLoader"
  - id: M4
    text: "Live: the border appears around a window focused by hover, is hidden where windows in front cover it, and follows the window when it moves or resizes"
must_not:
  - id: N1
    text: "frame() returns non-nil when focusIndicator is false, when paused, after reset(), or when bounds() returns nil (paired: M1 returns non-nil)"
  - id: N2
    text: "Tracking survives a .focusAndRaise decision, a failed .focus, or a mouse-down on a different or unknown window (paired: a mouse-down on the tracked window keeps it)"
  - id: N3
    text: "Live: the panel becomes key, activates HoverFocus, intercepts a click, or changes which window or app is frontmost"
  - id: N4
    text: "Live: the border shows on another Space, for a raiseApps window, or stays after the focused window closes or minimizes"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    command: "make build && make selftest rc 0 with new rows: 'Indicator tracks successful focus', 'Indicator frame converts and outsets' (the M1 numbers), 'Indicator follows latest focus', 'Indicator clears on raise', 'Indicator clears on failed focus', 'Indicator clears on click elsewhere', 'Indicator keeps on click on tracked', 'Indicator clears on unknown click', 'Indicator nil when disabled', 'Indicator nil when paused', 'Indicator nil after reset', 'Indicator nil when window gone', 'focusIndicator defaults true', 'focusIndicator false parses', 'focusIndicator non-boolean rejected', plus the existing round-trip row. Mutants on a scratch copy, each red then restored byte-identical: (a) decided() ignores .focusAndRaise -> 'clears on raise' fails; (b) mouseDown() never clears -> 'click elsewhere' and 'unknown click' fail; (c) frame() ignores enabled -> 'nil when disabled' fails; (d) cocoaFrame uses cgY directly -> 'converts and outsets' fails; (e) focusIndicator missing from knownKeys -> round-trip and 'false parses' fail; (f) frame() ignores paused -> 'nil when paused' fails; (g) decided() ignores succeeded -> 'failed focus' fails"
    intent: "The rules for when the border shows are tested without a screen: it marks the window you just hovered into focus, moves when focus moves, and disappears when you click elsewhere, pause, turn it off, or the window goes away."
  - id: E2
    proves: [M4, N3, N4]
    kind: live
    command: "Operator on m2 (macOS 26.5.1) with the U2 build installed (make install, launchctl kickstart -k), Claude reading logs and window state over SSH: (1) TextEdit behind iTerm2, hover TextEdit: accent border around TextEdit, the iTerm2-covered part shows no border, typing lands in TextEdit, iTerm2 stays frontmost; (2) drag and resize TextEdit: border follows; (3) click iTerm2: border disappears; (4) hold fn (pause): border disappears; (5) set focusIndicator false and reload: no border on hover; set true again; (6) a raiseApps window: no border; (7) close the focused window: border disappears; (8) switch Space: no border on the new Space; (9) clicks at the border edge reach the window under it. Claude confirms over SSH that HoverFocus never became the frontmost app during the run (NSWorkspace frontmost bundle sampled)."
    intent: "On m2, a thin coloured outline shows which window will take your typing, it moves with that window, it never gets in the way of clicks or steals focus, and it goes away when it should."
interface: "New: FocusIndicator.swift (IndicatorRect, FocusIndicatorModel, IndicatorGeometry), FocusIndicatorPanel.swift; Config.focusIndicator (config key focusIndicator, default true). No change to focus decisions."
```

## Worker definition of done

Report `make build` and `make selftest` rc and the passed/failed counts before and after; list each new row; show each
mutant failing its rows and `git diff --stat` after restoring; list every error seen. Commit nothing; Claude lands.
