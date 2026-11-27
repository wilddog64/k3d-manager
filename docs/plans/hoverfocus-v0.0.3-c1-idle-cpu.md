# hoverfocus v0.0.3 C1 — stop the idle CPU drain (menu-bar icon redraw loop; adaptive tick)

**Status:** SPEC rev 1 — from blind reviews of the bug doc by Fable and Neon (dispatch `hf003-cpu-review-neon`), both
NEEDS FIXES, folded in below, plus Claude's control and profiles (2026-11-27). Intents approved; dispatched to Luna (`hf003-c1`).
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.3-plan.md`](hoverfocus-v0.0.3-plan.md); fixes
[`2026-11-27-hoverfocus-idle-cpu-57-percent-from-50ms-indicator-redraw.md`](../bugs/2026-11-27-hoverfocus-idle-cpu-57-percent-from-50ms-indicator-redraw.md)
(proposed P1: shipped since v0.0.1; the only workaround is quitting the app; blocks the v0.0.3 tag).
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.3` (head `a4244b6`)
**Risk:** medium (main-thread timing of focus, border and menu bar; no install or signing change)
**Implementer:** Luna (codex, `gpt-6-luna`).
**Verifier:** Claude, from `## Acceptance` only; live budget measured by Claude on m4, behaviour checks by the operator.
**Filed:** 2026-11-27
**Intent approved:** operator, 2026-11-27
**Approval:** operator 2026-11-27 "can you have fable, neon review P2 bug then dispatch to Luna"; "approved" (intents)

## Context (you cannot read the bug doc; this is what it established)

HoverFocus is a menu-bar app (`Sources/hoverfocus/`, AppKit) over a pure core (`Sources/HoverFocusCore/`, tested by
`swift run hoverfocus-selftest`, `Sources/hoverfocus-selftest/main.swift`) and a platform layer
(`Sources/HoverFocusPlatform/Controller.swift`, `FocusIndicatorPanel.swift`).

Measured on m4 (macOS 26.5.2), idle, pointer untouched, `top -c d` 5 s samples: **51–58% CPU** steadily, with the
focus border on or off (`focusIndicator: false` changed nothing), and immediately after a relaunch. `sample <pid>`
(1 ms) of the main thread:

1. **≈52% — menu-bar icon redraw loop (primary).** `__NSFireDelayedPerform` → `-[NSStatusItem _updateReplicants]` →
   `_redrawReplicantSnapshot` → `CALayer renderInContext:`, driven by the KVO closure at `AppDelegate.swift:49-52`
   (`button.observe(\.effectiveAppearance)` → `updateIcon()`), which builds a new image and assigns `button.image`
   (`:234`) every time. Assigning the image makes AppKit rebuild the status item replicants, which re-resolves
   `effectiveAppearance`, which fires the observer again. `updateIcon` never checks whether anything changed. The 2 s
   trust timer (`:38-44` → `updateUI()` → `updateIcon()` at `:187`) also re-assigns the image every 2 s.
2. **≈9% — the 50 ms tick (secondary).** `Controller.swift:85` runs `onTick` every 50 ms forever. Each tick
   `systemState()` (`:236-250`) makes three full `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` copies
   (`menuWindowIsAt` `:292-293` twice, Mission Control `windowAtLevel` `:242`), each bridged to `[[String: Any]]`, an
   `NSRunningApplication` lookup per dock-level window (`:314`), and one synchronous AX call into the frontmost app
   (`frontmostWindowID` `:252-261`); with a tracked window, `windowBounds` (`:130`) adds a fourth list call and
   `FocusIndicatorPanel.show` issues four `order(.above, relativeTo:)` calls (`:64-66`). `setFrame` is already guarded
   by `lastFrame` (`FocusIndicatorPanel.swift:49-50`).

Things the tick does without any pointer event (so "tick only after pointer events" is wrong): dwell completion
(`Engine.tick`, `Engine.swift:85-101`, fires while the pointer is still); `indicator.observeFocused` (`Controller.swift:111`)
dropping the border on Cmd-Tab / close and its 1000 ms unconfirmed timeout (`FocusIndicator.swift:50`); the border
following a window moved or resized by keyboard or another tool (`:113-126`); hiding the border on pause (`:102-106`;
`isPaused` is a plain stored var, `:29`, set from `AppDelegate.swift:244/248/252`). The tap re-enable path (`:142-145`)
is event-driven and does not depend on the timer.

## Fix

### Part A — icon loop (primary)

1. Add to `HoverFocusCore` a pure value `MenuBarIconKey(style:, darkBar:, dimmed:)` and a small state holder
   `MenuBarIconState` with `mutating func needsApply(_ key: MenuBarIconKey) -> Bool` (true the first time and whenever
   the key differs from the last applied key; false otherwise) and `mutating func invalidate()` (next call returns true).
2. `AppDelegate.updateIcon()` computes the key and returns without building an image or touching `button.image` when
   `needsApply` is false. Build and assign only on change.
3. The appearance observer and the 2 s trust timer both go through `updateIcon()` and therefore stop re-assigning an
   unchanged image. `updateUI()` keeps updating menu text as today.

### Part B — tick (secondary)

4. Add to `HoverFocusCore` a pure `TickPolicy.interval(candidatePending: Bool, tracked: Bool, msSinceLastPointerEvent:
   UInt64?) -> Double?`: `0.05` when a dwell candidate is pending or a pointer event arrived in the last 500 ms; `0.25`
   when a window is tracked by the border and the pointer is idle; `nil` (timer stopped) otherwise. Add
   `Engine.hasPendingCandidate` (read-only).
5. `Controller` replaces the fixed timer with one re-armed from `TickPolicy` after every tick and from `handle()` on each
   pointer event, `apply(_:)`, `applyDecision(_:)` and `stop()`. Timer `tolerance` ≈ 10–20% of the interval. Call
   `onTick` with `MainActor.assumeIsolated` instead of `Task { @MainActor in … }`.
6. `isPaused` gets a `didSet` that resets the indicator, hides the panel and re-arms the timer, so pause never waits for
   a tick.
7. One on-screen window list per tick: take a single `CGWindowListCopyWindowInfo` snapshot and evaluate the menu check,
   the Mission Control check and the tracked window's bounds from it. Skip the menu and Mission Control checks when no
   dwell candidate is pending (they only feed `Engine.permitted`). Resolve the Dock pid once per snapshot, not per
   window.

Do not change: focus semantics, `dwellMs` behaviour, the indicator's frame or z-order behaviour (the four `order` calls
stay as they are in this child), config keys, menus, install or signing.

## Files

- `Sources/HoverFocusCore/MenuBarIconState.swift` (new)
- `Sources/HoverFocusCore/TickPolicy.swift` (new)
- `Sources/HoverFocusCore/Engine.swift` (`hasPendingCandidate` only)
- `Sources/hoverfocus/AppDelegate.swift`
- `Sources/HoverFocusPlatform/Controller.swift`
- `Sources/hoverfocus-selftest/main.swift`

## Contract readers

- `Engine` gains a read-only `hasPendingCandidate`; readers: `Controller.swift`, selftest. No other API changes.
- `button.image` assignment moves behind `MenuBarIconState`; the icon itself (`MenuBarIcon.makeImage`) is unchanged.

## What NOT to Do

- Do not touch `FocusIndicatorPanel.swift`, `FocusIndicator.swift`, `Makefile`, install or signing scripts.
- Do not run, install, kill or relaunch HoverFocus; do not read Keychain values; no network.
- Do not weaken or delete existing selftest cases. Do not commit.

## Acceptance

```yaml
must:
  - id: C-M1
    text: "MenuBarIconState.needsApply returns true for the first key and for every changed key (style, darkBar or dimmed), and true again after invalidate()"
  - id: C-M2
    text: "TickPolicy returns 0.05 with a pending candidate or a pointer event < 500 ms ago, 0.25 when tracked and idle, nil when neither"
  - id: C-M3
    text: "on m4, idle with the border off, HoverFocus averages <= 0.5% CPU and <= 2 idle wakeups/s; with the border up on a still window, <= 2.0% CPU and <= 10 idle wakeups/s; it is not listed under Using Significant Energy after 10 idle minutes"
  - id: C-M4
    text: "dwell focus still fires with a still pointer; the border follows a dragged window and a keyboard-moved window within ~300 ms; clears on Cmd-Tab and close; pause hides the border at once; menu bar icon still switches dimmed/undimmed on pause and follows light/dark menu bar"
must_not:
  - id: C-N1
    text: "100 consecutive needsApply calls with an unchanged key return true more than once"
    red_on_current: "red by mutation: make needsApply always return true (today's behaviour) — the selftest case fails"
  - id: C-N2
    text: "TickPolicy returns a non-nil interval with no pending candidate, no tracked window and no recent pointer event"
    red_on_current: "red by mutation: make interval a constant 0.05 (today's timer) — the selftest case fails"
  - id: C-N3
    text: "a stationary pointer prevents dwell focus (Engine.tick no longer fires at dwellMs)"
    red_on_current: "green on current and after the fix — positive control kept in the selftest"
  - id: C-N4
    text: "the running app on m4 idles above 5% CPU in any 5 s sample after warm-up"
    red_on_current: "red: 51-58% CPU per 5 s sample on a4244b6 (Claude, 2026-11-27 03:22Z and 19:44 PST)"
evidence:
  - id: C-E1
    proves: [C-M1, C-M2, C-N1, C-N2, C-N3]
    kind: offline
    command: "swift build && swift run hoverfocus-selftest passes; each mutant (needsApply always true; TickPolicy constant 0.05) turns its case red; reverted"
    intent: "Tests prove HoverFocus redraws its menu-bar icon only when its look actually changes and stops its timer when nothing is happening."
  - id: C-E2
    proves: [C-M3, C-N4]
    kind: live
    command: "Claude on m4 after the operator installs the fix build: top -l 7 -s 10 -c d -stats pid,cpu,idlew,power -pid <pid>, first sample discarded, pointer untouched, border off then border up; sample <pid> 5 shows no _updateReplicants loop; before numbers from the bug doc"
    intent: "HoverFocus no longer drains the battery: it sits near zero CPU when you are not moving the mouse and drops off macOS's energy list."
  - id: C-E3
    proves: [C-M4]
    kind: live
    command: "operator on m4: hover-focus a window and type; drag a window with the border up; move a window by keyboard; Cmd-Tab away; pause and resume from the menu; switch light/dark mode"
    intent: "Hover focus, the blue border and the menu-bar icon behave exactly as before."
interface:
  - "HoverFocusCore: MenuBarIconKey, MenuBarIconState.needsApply/invalidate, TickPolicy.interval, Engine.hasPendingCandidate"
```

## Worker definition of done

`swift build` clean; `swift run hoverfocus-selftest` passes; both mutants run and reverted (report the failing case
names); `git status` shows only the files in `## Files`.
