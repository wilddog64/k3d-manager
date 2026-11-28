# hoverfocus v0.0.3 L4 — resolve the hovered window through AXWindow, not the 8-level parent walk

**Status:** spec rev 2 — Fable and Neon reviewed rev 1 independently (2026-11-25, both NEEDS FIXES; shared finding: the
fixture window had no parent, so a walk without its role check stayed green; all findings applied); not dispatched
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.3-plan.md`](hoverfocus-v0.0.3-plan.md) (batch L4, added after the L3 live check)
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.3` at `7b42f63` (L3 `3951b67`, U1 `4e66919`, F2 `7b42f63`)
**Risk:** low (one lookup function plus a pure helper; no private API change)
**Implementer:** Flash (`agy`, `gemini-3.8-flash-medium`). **Verifier:** Claude, from `## Acceptance` only.
**Filed:** 2026-11-25
**Intent approved:** operator, 2026-11-25
**Approval:** operator 2026-11-25 ("go ahead to write L4 spec, and have either Fable or Neon or both review indenpendly. after that dispatch to Flash")

## Fixes

| Input | Defect (v0.0.3 `7b42f63`; code from `4cbd377`) |
|---|---|
| Electron recurrence, `docs/hoverfocus/bugs/2026-11-24-hoverfocus-electron-apps-no-focus.md` § Recurrence — v0.0.3 live check | Hovering Slack's web content never focuses Slack; hovering its window buttons does. `Controller.lookup` (`Controller.swift:130-176`) climbs at most 8 parents (`:146`) and reads `kAXSubroleAttribute` from wherever the climb stopped (`:165`). For Slack content that is an `AXGroup`, so `isStandardWindow` is false (`:174`) and `Engine.permitted` (`Engine.swift:26`) refuses the target with no log line |

## External behaviour (proof, before dispatch)

Probe `~/hf-probe/hf-p4-lookup.swift` on m2-air (macOS 26.5.1 25F80), operator at the keyboard, 2026-11-25, a
read-only replay of `lookup` (output recorded in the bug doc's Recurrence section):

| Pointer on | `AXWindow` depth | 8-level walk stops at | `_AXUIElementGetWindow` on stop element | `kAXWindowAttribute` on hit |
|---|---|---|---|---|
| iTerm2 text | 4 | `AXWindow` | rc 0, 269245 | rc 0, 269245 |
| Slack DM content | 20 | `AXGroup` | rc 0, 280187 | rc 0, 280187 |
| Slack window button | 1 | `AXWindow` | rc 0, 280187 | rc 0, 280187 |
| Safari page content (second run, same day) | 11 | `AXGroup` | rc 0, 254003 | rc 0, 254003 |

So `kAXWindowAttribute` on the hit element returns the containing window in all three cases, and
`_AXUIElementGetWindow` answers with the window id even on a non-window element (which is why the id was right while
the subrole was wrong). `AXUIElementCopyElementAtPosition` took 0-50 ms; the 0.2 s timeout is not a factor. Safari
page content has the same defect (depth 11); the earlier Safari pass hovered its title bar. VS Code is not probed yet:
it is exploratory in L4-EL, so a VS Code failure there is a new finding, not an L4 regression.

## Before You Start

1. `git log --oneline -1` shows `7b42f63`; `swift build --disable-sandbox` and `swift run --disable-sandbox hoverfocus-selftest`
   pass, ending `selftest: 99 passed, 0 failed`. Every `swift` command carries `--disable-sandbox` and runs with
   `CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-mc"`.
2. Read `Sources/HoverFocusPlatform/Controller.swift` (`lookup`, `applyDecision`), `Sources/HoverFocusCore/Engine.swift`
   (`permitted`), `Sources/HoverFocusCore/RecentCache.swift` (style of a small public Core type) and
   `Sources/hoverfocus-selftest/main.swift`.
3. Do not edit any file outside `## Files`.

## Behaviour

### 1. Pure resolver (new `Sources/HoverFocusCore/WindowResolver.swift`)

```swift
public enum WindowResolver {
    public static let windowRole = "AXWindow"
    public static let maxParentDepth = 8
    /// Returns the element to treat as the hovered window.
    /// 1. If window(hit) returns an element whose role(…) == windowRole, return it.
    /// 2. Otherwise walk from hit: if role(e) == windowRole return e; else e = parent(e); stop after maxParentDepth
    ///    parent steps or when parent returns nil, and return the element reached (the pre-L4 behaviour).
    public static func resolve<E>(hit: E,
                                  window: (E) -> E?,
                                  role: (E) -> String?,
                                  parent: (E) -> E?) -> E
}
```

The fallback walk is exactly the pre-L4 loop (`for _ in 0..<8`: check role, then step to parent; the role of the
element reached after the 8th step is not checked inside the loop), so a hit whose window attribute is missing behaves
as today.

### 2. Controller uses it

In `lookup`, replace the parent loop (`Controller.swift:145-157`) with one `WindowResolver.resolve` call whose closures
wrap `AXUIElementCopyAttributeValue` for `kAXWindowAttribute`, `kAXRoleAttribute` and `kAXParentAttribute` (each
closure returns nil unless the call is `.success` and, for element results, `CFGetTypeID == AXUIElementGetTypeID()`;
cast with `unsafeDowncast` as the file already does), with labels in the order `window:role:parent:`. Keep
`originalOwner` read from the raw hit (`Controller.swift:139-140`, used by the `idResult` fallback at `:161`); the
loop's `kAXWindowRole` reference goes away with the loop. The window id (`hf_ax_window_id`), subrole, owner pid,
`elements.set` and the returned `WindowTarget` all use the resolved element. Everything else in `lookup` (hit-test,
the `enableAccessibilityTree` calls on failure, messaging timeout) is unchanged.

Side effect, intended: `elements` now caches the window element rather than a deep child, so the `raiseApps` branch's
`kAXRaiseAction` targets the window.

### 3. Selftest rows (`Sources/hoverfocus-selftest/main.swift`)

Add `@MainActor func windowResolverChecks()` with the rows below and call it once immediately before the final
`print("selftest: …")` line, alongside the existing `coordinatorChecks()` call. One `check(…, "<name>")` per row, with
exactly these names. Model the tree with `Int` node ids and three dictionaries (`parent: [Int: Int]`,
`role: [Int: String]`, `windowAttr: [Int: Int]`); the closures look them up. Every `AXWindow` node has a parent whose
role is `AXApplication` (as on macOS), so a walk that ignores the role check climbs past the window.

| Check name | Tree (hit is node 0; `parent[i] = i + 1` unless stated) | Expected |
|---|---|---|
| `Resolver deep content uses window attribute` | `role[0...19] = AXGroup`, `role[20] = AXWindow`, `role[21] = AXApplication`; `windowAttr[0] = 20` | 20 |
| `Resolver shallow walk finds window` | `role[0...3] = AXGroup`, `role[4] = AXWindow`, `role[5] = AXApplication`; no window attribute | 4 |
| `Resolver deep fallback stops after 8 steps` | as the first row but no window attribute | 8 |
| `Resolver ignores non-window attribute` | `role[0...2] = AXGroup`, `role[3] = AXWindow`, `role[4] = AXApplication`; `windowAttr[0] = 1` | 3 |
| `Resolver hit is the window` | `role[0] = AXWindow`, `role[1] = AXApplication`; no window attribute | 0 |
| `Resolver walk stops at nil parent` | `role[0...2] = AXGroup`, no parent for node 2; no window attribute | 2 |

After the change the selftest ends `selftest: 105 passed, 0 failed`.

## Files

| File | Change |
|---|---|
| `Sources/HoverFocusCore/WindowResolver.swift` | new (Behaviour 1) |
| `Sources/HoverFocusPlatform/Controller.swift` | `lookup` only (Behaviour 2) |
| `Sources/hoverfocus-selftest/main.swift` | rows in Behaviour 3 |

## Contract readers

- `Controller.lookup` → `tapState.target` (`Controller.swift:112`) → `Engine.observe`; `WindowTarget` fields unchanged.
- `Controller.TapState.target` caches the lookup result for 16 ms; `lookup` gains one AX call (`kAXWindowAttribute`,
  plus `kAXRoleAttribute` on its result) on the main thread under the existing 0.2 s timeout.
- `Controller.elements` (`RecentCache<UInt32, AXUIElement>`, declaration line unchanged): writer `lookup`, reader the
  raise branch of `applyDecision`; it now holds the window element (see Behaviour 2).
- `Engine.permitted` (`Engine.swift:26`, `isStandardWindow`): unchanged; now receives `true` for standard windows whose
  hit is deep in web content.
- No config key, CLI flag, `Interface.swift` or CSkyLight change.

## What NOT to Do

- No edit to `Engine.swift`, `Interface.swift`, CSkyLight, `applyDecision`, `enableAccessibilityTree` or any file
  outside `## Files`. Do not raise `maxParentDepth` as the fix.
- Out of scope: a log line when the resolved element is not a window (the fallback still drops such hits silently, as
  the deep-fallback row characterises); it goes to a later spec if L4-EL shows an app that needs it.
- Do not run the app against the window server; use `swift run --disable-sandbox hoverfocus-selftest`.
- Run every command under
  `sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/sudo") (literal "/bin/launchctl"))'`.

## Acceptance

```yaml
must:
  - id: L4-M1
    text: "WindowResolver.resolve returns window(hit) when that element's role is AXWindow, and otherwise the result of the pre-L4 walk (at most 8 parent steps, stop at an AXWindow or a nil parent)"
  - id: L4-M2
    text: "Controller.lookup takes the window id, subrole, owner pid and the cached element from the element WindowResolver.resolve returns, with kAXWindowAttribute as the window closure"
must_not:
  - id: L4-N1
    text: "a hit 20 levels below its window, with a window attribute present, resolves to an element that is not the window (the v0.0.3 behaviour that drops Slack content) (paired: with no window attribute the same deep hit still resolves to the node 8 steps up, as before)"
  - id: L4-N2
    text: "a window attribute that returns a non-window element is used as the window (paired: the shallow walk still finds the window at depth 3)"
evidence:
  - id: L4-E1
    proves: [L4-M1, L4-N1, L4-N2]
    kind: offline
    command: "CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-mc\" swift build --disable-sandbox && CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-mc\" swift run --disable-sandbox hoverfocus-selftest — rc 0, last line 'selftest: 105 passed, 0 failed', the six Resolver rows named in Behaviour 3 present. Red controls, each restored byte-identical: (a) ignore the window closure (walk only) — 'Resolver deep content uses window attribute' fails, 'Resolver deep fallback stops after 8 steps' still passes; (b) return window(hit) without checking its role — 'Resolver ignores non-window attribute' fails; (c) walk 7 parent steps instead of 8 — 'Resolver deep fallback stops after 8 steps' fails; (d) delete the walk's role == windowRole check — 'Resolver shallow walk finds window', 'Resolver ignores non-window attribute' and 'Resolver hit is the window' fail, 'Resolver walk stops at nil parent' still passes. Pre-fix code does not compile against these rows (WindowResolver is new), so the must_nots are shown red by the controls"
    intent: "HoverFocus finds the right window under the pointer even when the pointer is deep inside an app's web content, and a later change that brings back the old behaviour is caught by the tests."
  - id: L4-E2
    proves: [L4-M2]
    kind: offline
    command: "code reading of lookup quoted with line numbers against Behaviour 2; git grep -n 'kAXWindowAttribute' -- Sources/HoverFocusPlatform/Controller.swift prints one line (prints nothing on 7b42f63); git grep -n 'for _ in 0..<8' -- Sources/HoverFocusPlatform/Controller.swift prints nothing; git grep -n 'WindowResolver.resolve' -- Sources/HoverFocusPlatform/Controller.swift prints one line; git grep -n 'kAXWindowRole' -- Sources/HoverFocusPlatform/Controller.swift prints nothing (one hit at :149 on 7b42f63); the quoted lookup shows hf_ax_window_id, the subrole read, AXUIElementGetPid for owner and elements.set all taking the resolved element"
    intent: "The app itself uses the new window lookup, not only the tests."
  - id: L4-EL
    proves: [L4-M2, L4-N1]
    kind: live
    command: "operator on m2, v0.0.3 build with L4 (Claude reads the unified log over SSH): relaunch Slack and VS Code first, and hover their content before their window buttons (cold start). Slack message area and Safari page content, each behind iTerm2: rest the pointer, type a word — it lands in the hovered app and the window stays behind; TextEdit and Chrome as controls. VS Code editor text is exploratory (not probed): a failure there is filed as a new finding with an hf-p4 probe, not counted against L4. Negative controls: with the pointer on an open Slack menu or popover, the Dock and the desktop, focus does not move. raiseApps: with Slack added to raiseApps, hovering Slack content brings it to the front with no 'focus failed' line. A silent no-focus with no 'focus failed' line means the lookup dropped the hit; probe that spot with hf-p4 before blaming focus delivery"
    intent: "On m2, resting the pointer anywhere on a Slack or VS Code window lets you type into it without clicking and without bringing it to the front."
interface: "HoverFocusCore adds public enum WindowResolver (windowRole, maxParentDepth, resolve). No change to Interface.swift, CSkyLight, config keys or CLI flags."
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each red control's failing output and `git diff --stat` after restoring it. Commit nothing; Claude lands.
