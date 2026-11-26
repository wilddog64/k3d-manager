# hoverfocus v0.0.3 U2 — border overlay on the hover-focused window (D2)

**Status:** spec rev 2 — Fable and Neon reviewed rev 1 independently (2026-11-26, both NEEDS FIXES; shared findings: stale
border after keyboard focus changes, `enabled: false` left it on screen, vacuous row preconditions and config-reason check,
headless panel creation, missing contract readers, live-step errors; Fable: one panel over the window could capture
hit-testing; all applied). LANDED `4a3940f` on `v0.0.3` (Flash `hf003-u2`, 2026-11-26); E1 Claude-verified (128/0, mutants a-k red, static checks); E2 live pending
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.3-plan.md`](hoverfocus-v0.0.3-plan.md) (batch U2, decision D2 option 1)
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.3` at `2e30655` (L3 `3951b67`, U1 `4e66919`, F2 `7b42f63`, L4 `11e0e7c`)
**Risk:** medium (new on-screen window owned by HoverFocus; must never take focus, clicks or activation)
**Implementer:** Flash (`agy`, `gemini-3.8-flash-medium`). **Verifier:** Claude, from `## Acceptance` only.
**Filed:** 2026-11-26
**Intent approved:** operator, 2026-11-26
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

**Hit-testing (Fable B3), designed out rather than probed.** `Controller.ownerPidAt` (`Controller.swift:217-231`) returns the
first on-screen layer-0 window with alpha > 0 under a point; a probe (m4, 2026-11-26) confirmed a panel covering a Finder
window is returned there as the probe's own pid. Whether `AXUIElementCopyElementAtPosition` also lands on such a panel
could not be probed (the probe process is not Accessibility-trusted: rc -25211). So the border is **four thin strip
panels outside the window's edges**, never over its interior, and `ownerPidAt` skips HoverFocus's own pid.

Coordinates: `kCGWindowBounds` is in global display space with the origin at the top-left of the main display (the one
with the menu bar), y down; AppKit frames have the origin at the bottom-left of the same display, y up. Conversion:
`cocoaY = mainHeight - (cgY + height)`, `mainHeight = CGDisplayBounds(CGMainDisplayID()).height` (no `NSScreen` force
unwrap: `NSScreen.screens` can be empty with the display asleep). Secondary displays give negative or out-of-range values;
the formula still holds.

## Before You Start

1. `git -C <hoverfocus> log --oneline -1` shows `2e30655`. Read `Sources/HoverFocusPlatform/Controller.swift` (whole),
   `Sources/HoverFocusCore/Interface.swift` (`Config`, `Decision`), `Sources/HoverFocusCore/ConfigLoader.swift`,
   `Sources/hoverfocus/main.swift`, `Sources/hoverfocus/AppDelegate.swift:230-290`, and the config rows in
   `Sources/hoverfocus-selftest/main.swift:123-164` (`rejected(_:key:)` at `:26-37` matches `reason.contains(key)`).
2. `make build` and `make selftest` pass before any edit (record the passed count; 103 `check(` call sites today). In a
   sandboxed run use `swift build --disable-sandbox` and `swift run --disable-sandbox hoverfocus-selftest` with
   `CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-mc"`.
3. No change outside `## Files`. No private API, no new entitlement, no change to which window gets focus or when.

## Behaviour

### 1. Config: `focusIndicator` (default `true`)

- `Config` gains `public var focusIndicator: Bool`, init parameter `focusIndicator: Bool = true` (last parameter).
- `ConfigLoader`: add `"focusIndicator"` to `knownKeys` and `try readBoolean("focusIndicator") { config.focusIndicator = $0 }`
  (rejects a non-boolean with `focusIndicator must be boolean`).
- The default-config writer (`AppDelegate.swift:283-286`), `--print-config` (`main.swift:42-59`) and the selftest round
  trip (`selftest/main.swift:160-164`) encode the whole `Config`, so the loader must accept the key in the same change.

### 2. Pure model: `Sources/HoverFocusCore/FocusIndicator.swift` (new)

```swift
public struct IndicatorRect: Sendable, Equatable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double)
}

public struct FocusIndicatorModel: Sendable, Equatable {
    public private(set) var trackedWindowID: UInt32?
    public init()
    public mutating func decided(_ decision: Decision, succeeded: Bool, nowMs: UInt64)
    public mutating func mouseDown(onWindow windowID: UInt32?)
    public mutating func observeFocused(_ focusedWindowID: UInt32?, nowMs: UInt64)
    public mutating func reset()
    public func frame(enabled: Bool, paused: Bool, bounds: (UInt32) -> IndicatorRect?, mainHeight: Double) -> IndicatorRect?
}

public enum IndicatorGeometry {
    public static let thickness = 3.0
    public static func cocoaFrame(cgBounds: IndicatorRect, mainHeight: Double) -> IndicatorRect
    public static func strips(around window: IndicatorRect) -> [IndicatorRect]
}
```

- `decided`: `.focus(t)` succeeded → track `t.windowID`, unconfirmed, remember `nowMs`; `.focus` not succeeded → clear;
  `.focusAndRaise` → clear (the app is activated and draws itself active); `.none` → unchanged.
- `mouseDown(onWindow:)`: a click on any window other than the tracked one, including `nil`, clears; a click on the
  tracked window keeps it.
- `observeFocused` (called every tick with the controller's `focusedWindowID`, `Controller.swift:189,205-215`): `nil` →
  no change (AX can fail); equal to the tracked ID → mark confirmed; different and confirmed → clear (Cmd-Tab, Cmd-`,
  a new window, an app activating itself); different and unconfirmed for more than 1000 ms since `decided` → clear.
- `reset()`: clears.
- `frame`: returns `nil` without calling `bounds` when `!enabled`, `paused` or nothing is tracked; `nil` when
  `bounds(id)` is `nil` (closed, minimized, hidden, other Space); otherwise `cocoaFrame` of the bounds.
- `cocoaFrame`: `(x, mainHeight - (y + height), width, height)`.
- `strips(around:)`: four rects outside the window, in order top, bottom, left, right, `t = thickness`:
  top `(x - t, y + h, w + 2t, t)`, bottom `(x - t, y - t, w + 2t, t)`, left `(x - t, y, t, h)`, right `(x + w, y, t, h)`.

### 3. Platform panels: `Sources/HoverFocusPlatform/FocusIndicatorPanel.swift` (new)

`@MainActor final class FocusIndicatorPanel` owning four strip panels, **created lazily on the first `show`** (never in
`init` or `hide`; `--print-status` and the selftest construct controllers before any `NSApplication`). Each strip is a
private `NSPanel` subclass that overrides `canBecomeKey` and `canBecomeMain` to `false` and
`constrainFrameRect(_:to:)` to return the rect unchanged (a top strip touching the menu bar must not be pushed down).
Configuration: `styleMask [.borderless, .nonactivatingPanel]`, `isOpaque = false`, `hasShadow = false`,
`ignoresMouseEvents = true`, `hidesOnDeactivate = false`, `level = .normal`,
`collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]` (no `.canJoinAllSpaces`),
`backgroundColor = NSColor.controlAccentColor`.

- `show(windowFrame: NSRect, aboveWindow id: UInt32)`: `guard id != 0 else { hide(); return }`; when the frame changed
  since the last `show` (or the strips are hidden), `setFrame(_:display: true)` each strip to `strips(around:)`; then
  `order(.above, relativeTo: Int(id))` each strip every call (z-order can change under it). Never `makeKey`,
  `makeKeyAndOrderFront`, `orderFrontRegardless` or `NSApp.activate`.
- `hide()`: a no-op before the strips exist; otherwise `orderOut(nil)` each visible strip.

### 4. Controller hooks (`Sources/HoverFocusPlatform/Controller.swift`)

- Properties: `private var indicator = FocusIndicatorModel()`, `private let indicatorPanel = FocusIndicatorPanel()`,
  `private var indicatorEnabled: Bool`, set to `config.enabled && config.focusIndicator` in `init` and `apply`.
- `apply(_:)`: also `indicator.reset()` and `indicatorPanel.hide()` when `indicatorEnabled` becomes false.
- `applyDecision`: after computing `result`, `indicator.decided(decision, succeeded: result == 0, nowMs: <now>)`.
- `handle`: on `.leftMouseDown`, `.rightMouseDown`, `.otherMouseDown`, call `indicator.mouseDown(onWindow: target?.windowID)`
  before `engine.observe`, then `indicatorPanel.hide()` at once if nothing is tracked.
- `onTick`: first `guard isRunning else { return }` (a queued tick can run after `stop()`, `:81-83`). When `isPaused`
  (set only by the menu's Pause, `AppDelegate.swift:242-258`; the fn pause modifier is an `Engine` input and does not set
  it), `indicator.reset()` and `indicatorPanel.hide()` before the existing early return. Otherwise, after
  `applyDecision`, `indicator.observeFocused(state.focusedWindowID, nowMs:)`, then `frame(...)`: `nil` → `hide()`, else
  `show(windowFrame:aboveWindow:)` with the tracked ID. The live `bounds` reads
  `CGWindowListCopyWindowInfo([.optionIncludingWindow], id)`, parses `kCGWindowBounds` with
  `CGRect(dictionaryRepresentation:)`, and returns it only when `kCGWindowIsOnscreen` is true and alpha > 0.
- `ownerPidAt`: skip windows owned by `getpid()`.
- `stop()`: `indicator.reset()`, `indicatorPanel.hide()`.

### 5. Docs

- `docs/config.md`: a `focusIndicator` row (Boolean, `true`, "Draws a thin accent-colour border around the window
  focused by hover; set false to turn it off.") in alphabetical order.
- `config.example.json`: `"focusIndicator" : true` in sorted-key position.
- `README.md` § Known Limitations: the border is drawn by HoverFocus, so the focused app still looks inactive (title
  bar, cursor shape); the border disappears within about a second after a keyboard focus change.

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

- `Config` (new field): readers `ConfigLoader.load` (`ConfigLoader.swift:27-86`), `AppCoordinator` (`:36`, `:60`),
  `Controller.init`/`apply`, `AppDelegate.toggleEnabled` (`:237-240`, mutates `enabled` and calls `apply`); writers
  `AppDelegate.swift:283-286` (default config), `--print-config` (`main.swift:42-59`), selftest round trip
  (`selftest/main.swift:160-164`). v0.0.2 and earlier reject a config containing `focusIndicator` as "unknown key"
  (downgrade only; release notes).
- `HoverFocusController` is constructed headless by `--print-status` (`main.swift:9-34`) and the selftest (`:293`): no
  panel may be created there.
- No change to `Decision`, `Engine`, `WindowResolver`, `hf_focus_without_raise` or the event mask.

## What NOT to Do

- No change to which window gets focus or when; the indicator only observes.
- No strip over the window's interior; no strip that becomes key or main, activates HoverFocus, receives mouse events,
  uses `.canJoinAllSpaces`, or a level above `.normal`.
- No animation, no per-app colour, no menu item (config only, per D2).
- No `CGWindowListCopyWindowInfo` call in the event-tap callback.

## Acceptance

Every "clears" / "nil" row first tracks window A and asserts a non-nil frame, then applies the transition.

```yaml
must:
  - id: M1
    text: "After a successful hover focus, frame() returns the window's Cocoa frame: mainHeight 1000, CG bounds (100, 50, 400, 300) give (100, 650, 400, 300); strips(around:) of that gives top (97, 950, 406, 3), bottom (97, 647, 406, 3), left (97, 650, 3, 300), right (500, 650, 3, 300); a secondary display, CG (1500, 800, 400, 300), gives (1500, -100, 400, 300)"
  - id: M2
    text: "Tracking follows the latest successful focus, survives .none, a click on the tracked window, and an observed focus equal to it"
  - id: M3
    text: "focusIndicator parses: default true; true and false accepted; {\"focusIndicator\":1} rejected with the exact reason 'focusIndicator must be boolean'; an encoded Config() round-trips"
  - id: M4
    text: "Live: the border appears around a window focused by hover, is hidden where windows in front cover it, and follows moves and resizes"
must_not:
  - id: N1
    text: "frame() returns non-nil when disabled, paused, after reset(), or when bounds() returns nil, or calls bounds() when disabled, paused or untracked (paired: M1 non-nil)"
  - id: N2
    text: "Tracking survives .focusAndRaise, a failed .focus, a click on a different or unknown window, a confirmed then different observed focus, or 1000 ms unconfirmed (paired: M2)"
  - id: N3
    text: "A strip becomes key or main, activates HoverFocus, receives clicks, covers the window interior, joins all Spaces, or sits above .normal; or a panel is created headless"
  - id: N4
    text: "Live: the border stays after Cmd-Tab, menu Pause, enabled off, focusIndicator off, close, minimize, Cmd-H, or shows on another Space or for a raiseApps window"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    command: "make build && make selftest rc 0 with new rows: 'Indicator tracks successful focus', 'Indicator frame converts', 'Indicator frame converts negative cocoa Y', 'Indicator strips surround window', 'Indicator follows latest focus', 'Indicator keeps tracking on none', 'Indicator keeps on click on tracked', 'Indicator keeps on observed match', 'Indicator clears on raise', 'Indicator clears on failed focus', 'Indicator clears on click elsewhere', 'Indicator clears on unknown click', 'Indicator clears on confirmed focus change', 'Indicator clears when unconfirmed 1000 ms', 'Indicator ignores nil observed focus', 'Indicator nil when disabled', 'Indicator nil when paused', 'Indicator nil after reset', 'Indicator nil when window gone', 'Indicator skips bounds when idle' (counting closure), 'focusIndicator defaults true', 'focusIndicator false parses', 'focusIndicator non-boolean rejected' (key 'focusIndicator must be boolean'), plus the existing round trip. Mutants on a scratch copy, each red then restored byte-identical: (a) .focusAndRaise keeps tracking; (b) mouseDown never clears; (c) frame ignores enabled; (d) cocoaFrame uses cgY directly; (e) focusIndicator missing from knownKeys (round trip and 'false parses' fail, 'non-boolean rejected' fails on the reason); (f) frame ignores paused; (g) failed .focus leaves tracking unchanged; (h) reset() a no-op; (i) .none clears; (j) observeFocused never clears; (k) strips placed inside the window. Static checks on FocusIndicatorPanel.swift and Controller.swift (quoted lines): present ignoresMouseEvents = true, hidesOnDeactivate = false, .nonactivatingPanel, level = .normal, order(.above, relativeTo:, canBecomeKey ... false, constrainFrameRect, the ownerPidAt getpid() skip, guard isRunning in onTick, indicatorEnabled = ... enabled && ... focusIndicator; zero matches for canJoinAllSpaces, makeKey, orderFrontRegardless, NSApp.activate, .floating, .statusBar, NSPanel( in init or hide"
    intent: "The rules for when the border shows are tested without a screen: it marks the window you just hovered into focus, moves when focus moves, and disappears when you click elsewhere, switch apps with the keyboard, pause, turn it off, or the window goes away."
  - id: E2
    proves: [M4, N3, N4]
    kind: live
    command: "Operator on m2 (macOS 26.5.1), U2 build installed with make install in m2's GUI terminal, config.json backed up first and restored after; Claude over SSH samples NSWorkspace frontmost every 200 ms and the strips' window-list position and alpha. (1) TextEdit behind iTerm2, hover TextEdit: accent border around TextEdit, none where iTerm2 covers it, typing lands in TextEdit, iTerm2 stays in front of TextEdit (not raised over); (2) drag and resize TextEdit by its title bar and corner: border follows; (3) click iTerm2: border gone; (4) Cmd-Tab to another app: border gone within about a second; (5) menu Pause: gone; Resume, hover again: back; (6) menu Disable: gone; (7) focusIndicator false, reload: no border; restore; (8) a raiseApps window: no border; (9) Cmd-M and Cmd-H on the focused window: gone, and not back on restore until hovered; close: gone; (10) switch Space and hover there: border only on that Space; (11) clicks right at the border edge reach the window under it; (12) with the Samsung monitor plugged in, hover a window on it: border aligned; (13) a full-screen app Space: no stray border. HoverFocus is never the frontmost app in the samples; WindowServer CPU with the border idle stays within 2 points of before."
    intent: "On m2, a thin coloured outline shows which window will take your typing, it moves with that window, it never gets in the way of clicks or steals focus, and it goes away when it should."
interface: "New: FocusIndicator.swift (IndicatorRect, FocusIndicatorModel, IndicatorGeometry), FocusIndicatorPanel.swift; Config.focusIndicator (config key focusIndicator, default true). No change to focus decisions."
```

## Worker definition of done

Report `make build` and `make selftest` rc and the passed/failed counts before and after; list each new row; show each
mutant failing its rows and `git diff --stat` after restoring; list every error seen. Commit nothing; Claude lands.
