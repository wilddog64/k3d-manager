# hoverfocus M1a — decision engine, config loader, private API shim, event tap

**Status:** DRAFT rev 1, 2026-11-22 — Fable spec review pending
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release; no `docs/ideas.md` row.
**Parent:** [`hoverfocus-m1-prototype.md`](hoverfocus-m1-prototype.md) (design, facts, interface, file ownership)
**Repo / branch:** `wilddog64/hoverfocus` / task branch from `m1-base` (the interface commit)
**Version:** v0.1.0
**Risk:** low (user space; no sudo; no network); the private-API part can break on macOS updates and must fail closed
**Implementer:** Luna (logic). Runs in parallel with M1b (Flash); no shared files. **Verifier:** Claude (Sonnet
verifier from `## Acceptance` only).
**Filed:** 2026-11-22
**Intent approved:** pending
**Approval:** operator 2026-11-22 (see parent)

## Before You Start

1. `git log --oneline -1` shows the interface commit on `m1-base`; `swift build` succeeds.
2. Read the parent spec in full, then `Sources/HoverFocusCore/Interface.swift`. Do not edit it or `Package.swift`. If
   the interface cannot express something you need, stop and report; do not work around it.

## Behaviour

**Engine (`Sources/HoverFocusCore/Engine.swift`, replaces the stub; pure, no clock reads, time comes in the samples):**

1. A candidate starts when `observe` sees a standard window (`isStandardWindow`) whose `windowID` differs from
   `state.focusedWindowID`. It is reset whenever the pointer moves more than `stillnessPx` (Euclidean, from the point
   where the candidate started) or the window under the pointer changes.
2. The candidate fires once, from `observe` or `tick`, when `nowMs - startMs >= dwellMs` and every gate below is open.
   After firing, the same window does not fire again until the pointer has left it.
3. Gates (any closed → `.none`, and the candidate is dropped): `config.enabled` false; `buttonsDown` true and
   `ignoreWhenButtonDown` true (also drops until all buttons are up); the pause modifier held (`pauseModifier` maps to
   the matching `Modifiers` bit; `.none` never pauses); `state.menuOpen`; `state.missionControlActive`; target
   `nil` or not standard; target `bundleID` in `ignoreApps`.
4. A firing target whose `bundleID` is in `raiseApps` yields `.focusAndRaise`; otherwise `.focus`. Nothing else ever
   yields `.focusAndRaise`.
5. `Engine.init(config:)` and a way to replace the config (`mutating func update(_ config: Config)`) that drops any
   candidate.

**Config loader (`Sources/HoverFocusCore/ConfigLoader.swift`):**

6. Missing file → `Config()` defaults. Unreadable → `ConfigError.unreadable(path:)`. Not JSON, wrong type, unknown key
   or out of range → `ConfigError.invalid(path:reason:)` with the key named in `reason`. Ranges: `dwellMs` 0...5000,
   `stillnessPx` 0...200. Missing keys take their defaults (a partial file is valid).

**Private API shim (`Sources/CSkyLight/`):**

7. `hf_skylight_resolve()` `dlopen`s SkyLight and ApplicationServices by absolute path and `dlsym`s every symbol it
   uses once, caching the result; it returns `available=false` and the first missing symbol's name on any failure.
   No symbol is linked at build time (no `-framework SkyLight`, no `extern` declarations of private functions).
8. `hf_focus_without_raise(pid, wid)` returns non-zero without calling anything if resolve failed; otherwise performs
   the sequence of parent fact 3. A comment above the event-record bytes names the public source of the layout.

**Platform (`Sources/HoverFocusPlatform/`, replaces the stub):**

9. `AccessibilityPermission.isTrusted(prompt:)` wraps `AXIsProcessTrustedWithOptions`.
10. `HoverFocusController.start()` checks, in order: Accessibility trust (else `.accessibilityNotTrusted`), shim
    resolve (else `.privateAPIUnavailable(symbol:)`), a listen-only `CGEventTap` for `mouseMoved` plus the drag and
    button events (else `.eventTapFailed`). It never crashes or aborts on any of these. A 50 ms timer calls
    `Engine.tick`. When the tap is disabled by timeout, it re-enables it.
11. Window lookup: `AXUIElementCopyElementAtPosition` on the system-wide element, walk to its `AXWindow`, get the
    window id with `_AXUIElementGetWindow` (resolved through the shim, not linked), `AXSubrole == AXStandardWindow`
    → `isStandardWindow`. `SystemState.menuOpen` from whether the frontmost app has an open menu (an `AXMenu` under
    the pointer or a `kCGWindowLayer` above 0 window under the pointer); `missionControlActive` best effort (Dock
    windows at the Mission Control layer), documented as best effort in a code comment.
12. `.focus` → `hf_focus_without_raise`; `.focusAndRaise` → `NSRunningApplication(processIdentifier:).activate()` and
    `AXRaise` on the window. A failed focus call is logged once per window (os_log, subsystem
    `com.wilddog64.hoverfocus`) and never retried in a loop.
13. `isPaused` true stops decisions without removing the tap; `apply(_:)` calls `Engine.update`; `stop()` removes the
    tap and timer and is safe to call twice.

**Self-test (`Sources/hoverfocus-selftest/`):**

14. A small assert helper (`check(_ cond:, _ name:)`) counts passes and failures, prints one line per failure and a
    final `selftest: <p> passed, <f> failed`; exit 1 on any failure. Tests cover items 1–6 with synthetic samples and
    temp files, and item 7 through a test-only entry `hf_skylight_resolve_with_symbol_override(const char *bad)`
    (declared in the C header, used only by the self-test) that forces one symbol name to a non-existent name.

## Files

| File | Change |
|---|---|
| `Sources/HoverFocusCore/Engine.swift` | replace stub |
| `Sources/HoverFocusCore/ConfigLoader.swift` | replace stub |
| `Sources/CSkyLight/include/CSkyLight.h` | add the test-only override declaration |
| `Sources/CSkyLight/CSkyLight.c` | replace stub |
| `Sources/HoverFocusPlatform/Controller.swift` | replace stub |
| `Sources/HoverFocusPlatform/*.swift` | new files as needed (window lookup, event tap, focuser) |
| `Sources/hoverfocus-selftest/*.swift` | replace stub, add tests |

## Contract readers

- `Interface.swift` public names: reader M1b `Sources/hoverfocus/**` (after its land). This spec changes none.
- `~/.config/hoverfocus/config.json`: reader `ConfigLoader` (this spec), writer the operator; M1b documents the keys in
  `docs/config.md` from the `Config` defaults. A new key is a change to both.
- os_log subsystem `com.wilddog64.hoverfocus`: readers M1b's README ("how to see logs"). Writer this spec.

## What NOT to Do

- No edit to `Package.swift`, `Interface.swift` or any file outside the table. No new dependency.
- No code copied from AutoRaise, yabai or any other project; read for the method only.
- No `sudo`, no `launchctl`, no writes outside the worktree and the system temp dir. Do not run the app; the event
  tap needs Accessibility trust, which only the operator grants (live evidence).
- No `fatalError`, `precondition` or force-unwrap on any path that depends on the system (permissions, symbols,
  AX results).

## Acceptance

```yaml
must:
  - id: M1
    text: "a pointer resting on an unfocused standard window for dwellMs (within stillnessPx) yields .focus exactly once, from observe or tick; at dwellMs-1 it yields .none"
  - id: M2
    text: "moving more than stillnessPx or onto another window restarts the dwell; the already-focused window never fires; after firing the same window does not fire again until the pointer leaves it"
  - id: M3
    text: "each gate closes: enabled false, buttons down (and until all buttons are up), pause modifier held, menuOpen, missionControlActive, non-standard or nil target, ignoreApps; pauseModifier none never pauses"
  - id: M4
    text: "a raiseApps target yields .focusAndRaise; every other firing yields .focus"
  - id: M5
    text: "ConfigLoader: missing file gives defaults; partial file fills defaults; non-JSON, wrong type, unknown key, dwellMs 5001 or -1, stillnessPx 201 give ConfigError.invalid naming the key; unreadable gives ConfigError.unreadable"
  - id: M6
    text: "hf_skylight_resolve returns available=true on this Mac and, with one symbol overridden to a bad name, available=false naming that symbol; hf_focus_without_raise then returns non-zero"
  - id: M7
    text: "HoverFocusController.start throws (never crashes) for each failed precondition, checked in order: accessibilityNotTrusted, privateAPIUnavailable(symbol:), eventTapFailed"
must_not:
  - id: N1
    text: "the engine yields .focusAndRaise for a target not in raiseApps (paired: raiseApps target does)"
  - id: N2
    text: "the engine yields .focus while buttons are down with ignoreWhenButtonDown true (paired: same samples with buttons up do)"
  - id: N3
    text: "a private symbol is referenced outside Sources/CSkyLight/ or linked at build time (paired: the shim resolves it at runtime)"
  - id: N4
    text: "the engine fires before dwellMs or fires twice for one stay (paired: fires once at dwellMs)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2, N4]
    kind: offline
    command: "swift build && swift run hoverfocus-selftest, rc 0, final line 'selftest: <p> passed, 0 failed'. Red controls, each restored byte-identical (git diff --stat empty after): engine mutant '>= dwellMs' to '>= 0' turns M1/N4 tests red; removing the buttonsDown gate turns N2 red; returning .focusAndRaise for every target turns N1 red; dropping the unknown-key check turns M5 red; the stub Engine.swift from m1-base fails M1-M4"
    intent: "The rules that decide when a window gets focus (wait time, drags, the pause key, menus, ignore and raise lists, the config file) are tested without needing your screen."
  - id: E2
    proves: [N3, M6]
    kind: offline
    command: "git grep -nE '_SLPS|SLPS|SLS[A-Z]|GetProcessForPID|_AXUIElementGetWindow' -- Sources ':!Sources/CSkyLight' prints nothing; the symbols appear under Sources/CSkyLight only as dlsym strings; otool -L .build/debug/hoverfocus-selftest lists no SkyLight; red control: an extern declaration of _SLPSSetFrontProcessWithOptions added to a Platform file is found by the grep"
    intent: "The fragile private macOS calls live in one small file and are looked up at runtime, so a macOS update that removes them disables the tool instead of crashing it."
  - id: E3
    proves: [M7]
    kind: offline
    command: "selftest constructs HoverFocusController and calls start() in the test process (no Accessibility trust): it throws accessibilityNotTrusted, the process keeps running, isRunning stays false; code reading shows the three checks in the stated order"
    intent: "Without your permission granted, the tool refuses to start and says why, rather than crashing."
  - id: E-L1
    proves: [M1]
    kind: live
    command: "operator, after M1b lands: parent E-L1 to E-L4"
    intent: "On your Mac, typing goes to the window under the pointer without that window jumping to the front."
interface: "Interface.swift unchanged; Engine.update(_:) added; test-only C entry hf_skylight_resolve_with_symbol_override"
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each mutant's red result and `git diff --stat` after restoring it.
