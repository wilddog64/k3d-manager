# hoverfocus M1a — decision engine, config loader, private API shim, event tap

**Status:** DRAFT rev 2, 2026-11-22 — Fable spec review pending (rev 1 → rev 2: focus technique fixed to variant B from
the operator's probe; base is `m1-base` with M1b landed; `MenuModel.loadConfig` routed through `ConfigLoader`; start
order tested through `StartChecks`; no event records)
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release; no `docs/ideas.md` row.
**Parent:** [`hoverfocus-m1-prototype.md`](hoverfocus-m1-prototype.md) (design, facts, interface, file ownership).
Where this spec and parent fact 3 differ, this spec wins (see Focus technique below).
**Repo / branch:** `wilddog64/hoverfocus` / task branch from `m1-base` at `bef450c` (interface + M1b app shell + Apache-2.0)
**Version:** v0.1.0
**Risk:** low (user space; no sudo; no network); the private-API part can break on macOS updates and must fail closed
**Implementer:** Luna (logic). **Verifier:** Claude (independent verifier from `## Acceptance` only).
**Filed:** 2026-11-22
**Intent approved:** operator 2026-11-22 ("your intents approved"), for the evidence intent lines as written in rev 1; rev 2 keeps them verbatim
**Approval:** operator 2026-11-22 (see parent); "execute the steps … to make hoverfocus moving" 2026-11-22 (rev 2, Fable review, dispatch)

## Focus technique (proof of external behaviour)

Operator probe `probe/focus-flags` (`a531a4a`, `6c2e4b1`), run on m2-air, macOS 26.5.1 (25F80), 2026-11-22, two runs:

| Variant | Calls | Typing went to target | Target raised |
|---|---|---|---|
| A | `_SLPSSetFrontProcessWithOptions(psn, wid, 0x200 kCPSUserGenerated)` | no | no |
| **B** | `_SLPSSetFrontProcessWithOptions(psn, wid, 0x400 kCPSNoWindows)` | **yes (TextEdit, 4 of 4 valid runs)** | **no** |
| C | A + two `SLPSPostEventRecordTo` "make key" records | yes | no, but records returned rc 1002 |
| D | B + deactivate/activate + make-key records | yes | no; every record rc 1002, so D behaved as B |

Decision: **variant B only.** `hf_focus_without_raise(pid, wid)` resolves the PSN with `GetProcessForPID` and calls
`_SLPSSetFrontProcessWithOptions(&psn, wid, 0x400)`; it posts no event records and does not resolve
`SLPSPostEventRecordTo`. Known limitation (documented in `docs/` by this task, not fixed): an app that raises its own
window when it becomes active (Safari did once in the probe) will still come to the front; the user can put it in
`ignoreApps`.

## Before You Start

1. `git log --oneline -1` on your task branch shows `bef450c` (or a later `m1-base` commit); `swift build` and
   `swift run hoverfocus-selftest` succeed (the stub prints `selftest: 0 tests`).
2. Read the parent spec in full, then `Sources/HoverFocusCore/Interface.swift`, `Sources/hoverfocus/MenuModel.swift`
   and `Sources/hoverfocus/AppDelegate.swift`. Do not edit `Interface.swift` or `Package.swift`. If the interface cannot
   express something you need, stop and report; do not work around it.

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
5. `Engine.init(config:)` and `mutating func update(_ config: Config)`, which drops any candidate.

**Config loader (`Sources/HoverFocusCore/ConfigLoader.swift`), the only parser of the config file:**

6. Missing file → `Config()` defaults. Unreadable → `ConfigError.unreadable(path:)`. Not JSON, not a top-level object,
   wrong type, unknown key, unknown enum value (`pauseModifier`, `menuBarIcon`) or out of range →
   `ConfigError.invalid(path:reason:)` with the key named in `reason`. Ranges: `dwellMs` 0...5000, `stillnessPx`
   0...200. Missing keys take their defaults (a partial file is valid). All eight `Config` keys are accepted.
7. `MenuModel.loadConfig(at:)` (`Sources/hoverfocus/MenuModel.swift`) becomes `try ConfigLoader.load(from: url)`; its
   private `PartialConfig` decoder is deleted. `MenuModel.configPath()` / `configURL()` are unchanged.

**Private API shim (`Sources/CSkyLight/`):**

8. `hf_skylight_resolve()` `dlopen`s `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` and
   `/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices` by absolute path and `dlsym`s
   exactly `_SLPSSetFrontProcessWithOptions`, `GetProcessForPID` and `_AXUIElementGetWindow` once, caching the result;
   it returns `available=false` and the first missing symbol's name on any failure. No symbol is linked at build time
   (no `-framework SkyLight`, no `extern` declarations of private functions).
9. `hf_focus_without_raise(pid, wid)` returns non-zero without calling anything if resolve failed or `GetProcessForPID`
   fails; otherwise it returns the result of `_SLPSSetFrontProcessWithOptions(&psn, wid, 0x400)`. A comment names the
   flag (`kCPSNoWindows`) and cites this spec's probe table.
10. `hf_ax_window_id(element, &wid)` returns non-zero if resolve failed, otherwise the `_AXUIElementGetWindow` result.
11. `hf_skylight_resolve_with_symbol_override(name)` (already declared) resolves as in 8 but looks up `name`'s slot under
    a non-existent symbol name; it does not disturb the cached real result.

**Platform (`Sources/HoverFocusPlatform/`, replaces the stub):**

12. `AccessibilityPermission.isTrusted(prompt:)` wraps `AXIsProcessTrustedWithOptions`.
13. `HoverFocusController.init(config:checks:)` stores the checks; `start()` evaluates, in order,
    `checks.isTrusted()` (false → throw `.accessibilityNotTrusted`), `checks.missingPrivateSymbol()` (non-nil → throw
    `.privateAPIUnavailable(symbol:)`), `checks.canListenToEvents()` (false → throw `.eventTapFailed`), and stops at the
    first failure without evaluating later checks. It then creates a listen-only `CGEventTap` for `mouseMoved` plus the
    drag and button events (creation failure → `.eventTapFailed`). It never crashes or aborts. `liveChecks` wires
    `AccessibilityPermission.isTrusted(prompt: false)`, `hf_skylight_resolve().missing_symbol` and
    `CGPreflightListenEventAccess()`. A 50 ms timer calls `Engine.tick` with `MonotonicClock.nowMs()`. When the tap is
    disabled by timeout or user input, it re-enables it. `isRunning` is true only after a successful start.
14. Window lookup: `AXUIElementCopyElementAtPosition` on the system-wide element, walk to its `AXWindow`, window id via
    `hf_ax_window_id`, `AXSubrole == AXStandardWindow` → `isStandardWindow`. `SystemState.focusedWindowID` from the
    frontmost app's `AXFocusedWindow` via `hf_ax_window_id`. `menuOpen` from an `AXMenu` under the pointer or a
    `kCGWindowLayer` above 0 window under the pointer; `missionControlActive` best effort (Dock windows at the Mission
    Control layer), documented as best effort in a code comment.
15. `.focus` → `hf_focus_without_raise`; `.focusAndRaise` → `NSRunningApplication(processIdentifier:)?.activate()` and
    `AXRaise` on the window. A failed focus call is logged once per window (os_log, subsystem
    `com.wilddog64.hoverfocus`) and never retried in a loop.
16. `isPaused` true stops decisions without removing the tap; `apply(_:)` calls `Engine.update`; `stop()` removes the
    tap and timer, sets `isRunning` false, and is safe to call twice.

**Self-test (`Sources/hoverfocus-selftest/`):**

17. A small assert helper (`check(_ cond:, _ name:)`) counts passes and failures, prints one line per failure and a
    final `selftest: <p> passed, <f> failed`; exit 1 on any failure. Tests cover items 1–7 with synthetic samples and
    temp files (under the system temp dir), items 8–11 through the C entry points, and item 13 with stub `StartChecks`
    whose closures record that they were called.
18. The SkyLight check (`hf_skylight_resolve().available == true`) runs by default, so the existing CI step
    `swift run hoverfocus-selftest` on `macos-26` catches a runner image whose macOS dropped a symbol. `HOVERFOCUS_SELFTEST_SKIP_SKYLIGHT=1`
    skips only that check and prints `skylight: skipped`.

**Docs:** `docs/config.md` states that the app rejects unknown keys and out-of-range values (naming them in the menu
status line); `README.md` gains a "Known limitations" line for self-raising apps (see Focus technique).

## Files

| File | Change |
|---|---|
| `Sources/HoverFocusCore/Engine.swift` | replace stub |
| `Sources/HoverFocusCore/ConfigLoader.swift` | replace stub |
| `Sources/CSkyLight/CSkyLight.c` | replace stub |
| `Sources/HoverFocusPlatform/Controller.swift` | replace stub |
| `Sources/HoverFocusPlatform/*.swift` | new files as needed (window lookup, event tap, focuser) |
| `Sources/hoverfocus/MenuModel.swift` | `loadConfig` delegates to `ConfigLoader`; delete `PartialConfig` |
| `Sources/hoverfocus-selftest/*.swift` | replace stub, add tests |
| `docs/config.md`, `README.md` | the two doc lines above |

`Sources/CSkyLight/include/CSkyLight.h` already declares every entry point; no change.

## Contract readers

- `Interface.swift` public names: reader `Sources/hoverfocus/**` (AppDelegate, MenuModel, main.swift). This spec
  changes none.
- `~/.config/hoverfocus/config.json` (or `HOVERFOCUS_CONFIG`): reader `ConfigLoader` (after this spec the only parser;
  `MenuModel.loadConfig` delegates); writers the operator and `AppDelegate` (around line 245, writes the full `Config`
  with `JSONEncoder` when menu toggles change it, so every key it writes must load back). A new key is a change to
  `Config`, `ConfigLoader` and `docs/config.md`.
- os_log subsystem `com.wilddog64.hoverfocus`: reader README ("how to see logs"). Writer this spec.
- `HOVERFOCUS_SELFTEST_SKIP_SKYLIGHT`: new; reader the self-test only.

## What NOT to Do

- No edit to `Package.swift`, `Interface.swift`, `CSkyLight.h` or any file outside the table. No new dependency.
- No code copied from AutoRaise, yabai or any other project; read for the method only.
- No `SLPSPostEventRecordTo`, no synthetic event records, no `kCPSUserGenerated`.
- No `sudo`, no `launchctl`, no writes outside the worktree and the system temp dir. Do not run the app; the event
  tap needs Accessibility trust, which only the operator grants (live evidence).
- No `fatalError`, `precondition` or force-unwrap on any path that depends on the system (permissions, symbols,
  AX results, file contents).

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
    text: "ConfigLoader: missing file gives defaults; partial file fills defaults; non-JSON, top-level array, wrong type, unknown key, unknown pauseModifier or menuBarIcon value, dwellMs 5001 or -1, stillnessPx 201 give ConfigError.invalid naming the key; unreadable gives ConfigError.unreadable; a Config written by JSONEncoder loads back equal"
  - id: M6
    text: "hf_skylight_resolve returns available=true on this Mac and, with one symbol overridden to a bad name, available=false naming that symbol; hf_focus_without_raise and hf_ax_window_id return non-zero when resolve failed"
  - id: M7
    text: "HoverFocusController.start throws (never crashes) for each failed precondition, checked in order: accessibilityNotTrusted, privateAPIUnavailable(symbol:), eventTapFailed; later checks are not evaluated after the first failure; isRunning stays false"
  - id: M8
    text: "MenuModel.loadConfig returns exactly what ConfigLoader.load returns, and throws what it throws, for the same file"
must_not:
  - id: N1
    text: "the engine yields .focusAndRaise for a target not in raiseApps (paired: raiseApps target does)"
  - id: N2
    text: "the engine yields .focus while buttons are down with ignoreWhenButtonDown true (paired: same samples with buttons up do)"
  - id: N3
    text: "a private symbol is referenced outside Sources/CSkyLight/ or linked at build time (paired: the shim resolves it at runtime)"
  - id: N4
    text: "the engine fires before dwellMs or fires twice for one stay (paired: fires once at dwellMs)"
  - id: N5
    text: "the shim resolves or posts SLPSPostEventRecordTo or uses kCPSUserGenerated (paired: it resolves _SLPSSetFrontProcessWithOptions and passes 0x400)"
  - id: N6
    text: "MenuModel accepts a config file that ConfigLoader rejects (paired: both accept a valid partial file)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, M8, N1, N2, N4, N6]
    kind: offline
    command: "swift build && swift run hoverfocus-selftest, rc 0, final line 'selftest: <p> passed, 0 failed'. Red controls, each restored byte-identical (git diff --stat empty after): engine mutant '>= dwellMs' to '>= 0' turns M1/N4 tests red; removing the buttonsDown gate turns N2 red; returning .focusAndRaise for every target turns N1 red; dropping the unknown-key check turns M5 red; restoring the m1-base MenuModel.loadConfig body turns N6 red (unknown key accepted); the stub Engine.swift from m1-base fails M1-M4"
    intent: "The rules that decide when a window gets focus (wait time, drags, the pause key, menus, ignore and raise lists, the config file) are tested without needing your screen."
  - id: E2
    proves: [N3, N5, M6]
    kind: offline
    command: "git grep -nE '_SLPS|SLPS|SLS[A-Z]|GetProcessForPID|_AXUIElementGetWindow' -- Sources ':!Sources/CSkyLight' prints nothing; git grep -nE 'PostEventRecord|0x200|UserGenerated' -- Sources prints nothing; the three symbols appear under Sources/CSkyLight only as dlsym strings; otool -L .build/debug/hoverfocus-selftest lists no SkyLight; red controls: an extern declaration of _SLPSSetFrontProcessWithOptions added to a Platform file is found by the first grep; a dlsym of SLPSPostEventRecordTo added to CSkyLight.c is found by the second"
    intent: "The fragile private macOS calls live in one small file and are looked up at runtime, so a macOS update that removes them disables the tool instead of crashing it."
  - id: E3
    proves: [M7]
    kind: offline
    command: "selftest builds HoverFocusController with stub StartChecks for each of the three failure cases (and the all-pass-but-tap case is not run, since it would create a real tap); each start() throws the expected error, the process keeps running, isRunning stays false, and the recording stubs show later checks were not called; red control: swapping the first two checks in start() turns the order test red; liveChecks read in code wires the three named system calls"
    intent: "Without your permission granted, the tool refuses to start and says why, rather than crashing."
  - id: E-L1
    proves: [M1]
    kind: live
    command: "operator on m2-air after land and make install: parent E-L1 to E-L4 (grant Accessibility; hover TextEdit behind Terminal, typing goes to TextEdit and it stays behind)"
    intent: "On your Mac, typing goes to the window under the pointer without that window jumping to the front."
interface: "Interface.swift and CSkyLight.h unchanged; Engine.update(_:) added; MenuModel.loadConfig behaviour now equals ConfigLoader.load; env HOVERFOCUS_SELFTEST_SKIP_SKYLIGHT (selftest only)"
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each mutant's red result and `git diff --stat` after restoring it.
- Run SwiftPM with `--disable-sandbox` if your environment refuses nested sandboxes (`sandbox_apply: Operation not
  permitted`); say so in the report.
