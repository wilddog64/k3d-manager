# hoverfocus M1a — decision engine, config loader, private API shim, event tap

**Status:** READY rev 4, 2026-11-22 — Fable re-check of rev 3: "ready after should-fix" (E2 `-w` grep, confirmed by Claude on a fixture) plus 6 nits, all taken in rev 4. Fable review of rev 2: needs rework (3 blockers, 12 should-fix, 4 nits), all taken in rev 3 (rev 2 → rev 3: M8/N6 proved through `--print-config`, selftest may name symbols, untestable resolve-failure clause made code-read, engine traps, tick semantics, idempotent start, AX timeout/throttle, public tap check and raise, docs ranges, red controls; rev 1 → rev 2: focus technique fixed to variant B from
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
**Intent approved:** operator 2026-11-22 ("your intents approved"), for the evidence intent lines as written in rev 1; revs 2–4 keep them verbatim
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
`ignoreApps`. Also unproven by the probe (it skipped same-app targets and used one TextEdit window): moving focus
between two windows of the already-front app, or to an app's non-key window. These are listed as known limitations and
checked live (E-L1 step 3); do not "fix" them with event records.

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
2. The candidate fires once, from `observe` or `tick`, when elapsed time `>= dwellMs` and every gate below is open.
   After firing, the same window does not fire again until the pointer has left it. Elapsed time is a saturating
   difference (a time earlier than the candidate start counts as 0, never traps); a negative `dwellMs` (possible from
   `Config(dwellMs:)` in code) is treated as 0. `tick` has no sample of its own: it evaluates the gates with the last
   observed sample's `buttonsDown` and `modifiers`, the last observed target, and the `state` passed to it. The caller
   takes every `timeMs` / `nowMs` from `MonotonicClock.nowMs()`.
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
   "Wrong type" includes the cases `JSONSerialization` bridges silently: `"enabled": 1`, `"dwellMs": true`,
   `"dwellMs": 150.5` and `"stillnessPx": "4"` are all rejected naming the key. Non-JSON and a non-object top level are
   rejected with a reason that says so (there is no key to name).
7. `MenuModel.loadConfig(at:)` (`Sources/hoverfocus/MenuModel.swift`) becomes `try ConfigLoader.load(from: url)`; its
   private `PartialConfig` decoder is deleted. `MenuModel.configPath()` / `configURL()` are unchanged. `main.swift`
   `--print-config` already prints the loaded config (rc 0) or the error (rc 2) and needs no change; it becomes the
   way M8/N6 are proved, because the self-test target cannot import the `hoverfocus` executable target.

**Private API shim (`Sources/CSkyLight/`):**

8. `hf_skylight_resolve()` `dlopen`s `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` and
   `/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices` by absolute path and `dlsym`s
   exactly `_SLPSSetFrontProcessWithOptions`, `GetProcessForPID` and `_AXUIElementGetWindow` once (thread-safe, e.g.
   `pthread_once`), caching the result; it returns `available=false` and the first missing symbol's name on any failure,
   and `missing_symbol == NULL` when `available` is true. Every returned name points into the shim's static symbol
   table, never at a caller's string. No symbol is linked at build time
   (no `-framework SkyLight`, no `extern` declarations of private functions).
9. `hf_focus_without_raise(pid, wid)` returns non-zero without calling anything if resolve failed, `pid <= 0`, or
   `GetProcessForPID` fails; otherwise it returns the result of `_SLPSSetFrontProcessWithOptions(&psn, wid, 0x400)`. A comment names the
   flag (`kCPSNoWindows`) and cites this spec's probe table.
10. `hf_ax_window_id(element, &wid)` returns non-zero without calling through if `element` or `wid` is NULL or resolve
    failed; otherwise the `_AXUIElementGetWindow` result.
11. `hf_skylight_resolve_with_symbol_override(name)` (already declared) performs a fresh, uncached resolve in which the
    symbol equal to `name` is looked up under a non-existent name; it returns that result with `missing_symbol` pointing
    at the static table entry for `name`, and does not disturb the cached real result. An unrecognised `name` returns the
    real result. Because the cache is never broken, "returns non-zero when resolve failed" in 9 and 10 is proved by code
    reading, not by a test; the self-test never calls `hf_focus_without_raise` with a real pid.

**Platform (`Sources/HoverFocusPlatform/`, replaces the stub):**

12. `AccessibilityPermission.isTrusted(prompt:)` wraps `AXIsProcessTrustedWithOptions`.
13. `HoverFocusController.init(config:checks:)` stores the checks; `start()` evaluates, in order,
    `checks.isTrusted()` (false → throw `.accessibilityNotTrusted`), `checks.missingPrivateSymbol()` (non-nil → throw
    `.privateAPIUnavailable(symbol:)`), `checks.canListenToEvents()` (false → throw `.eventTapFailed`), and stops at the
    first failure without evaluating later checks. It then creates a listen-only `CGEventTap` for `mouseMoved` plus the
    drag and button events (creation failure → `.eventTapFailed`). It never crashes or aborts. `liveChecks` wires
    `AccessibilityPermission.isTrusted(prompt: false)`, `hf_skylight_resolve().missing_symbol` (NULL → nil), and a
    trial: create a listen-only `mouseMoved` tap and invalidate it at once (non-nil → true). Do not use
    `CGPreflightListenEventAccess` (it reports Input Monitoring, which a listen-only mouse tap was not shown to need).
    `start()` is a no-op when `isRunning` is already true (AppDelegate calls it again from Reload Config and the
    Accessibility timer). The tap's run-loop source and a 50 ms timer go on the main run loop; C callbacks enter
    through `MainActor.assumeIsolated`. The timer calls `Engine.tick` with `MonotonicClock.nowMs()`. When the tap is
    disabled by timeout or user input, it re-enables it. `isRunning` is true only after a successful start. Swift 6
    trial tap uses a no-op C callback and is released with `CFMachPortInvalidate`. Swift 6
    hints: use the literal key `"AXTrustedCheckOptionPrompt"` (the global `kAXTrustedCheckOptionPrompt` is a `var`);
    recording stubs in `@Sendable` closures need a lock-guarded `final class … : @unchecked Sendable` (`Mutex` is
    macOS 15+, target is macOS 14).
14. Window lookup: `AXUIElementCopyElementAtPosition` on the system-wide element at the `CGEvent.location` point
    (top-left origin, not `NSEvent.mouseLocation`), walk to its `AXWindow`, window id via `hf_ax_window_id`,
    `AXSubrole == AXStandardWindow` → `isStandardWindow`. `AXUIElementSetMessagingTimeout` on the system-wide element is
    about 0.2 s, and the lookup runs at most once per 16 ms (pointer moves in between reuse the last target), so a hung
    app cannot stall the menu or the tap. `SystemState.focusedWindowID` from the frontmost app's `AXFocusedWindow` via
    `hf_ax_window_id`. `menuOpen` best effort: an `AXMenu` under the pointer, or a window under the pointer at the
    pop-up-menu or main-menu window level with non-zero alpha (not any layer above 0: transparent overlays must not
    close the gate); `missionControlActive` best effort (Dock windows at the Mission Control layer). Both documented as
    best effort in a code comment. Platform keeps a small windowID → `AXUIElement` cache for `.focusAndRaise`.
15. `.focus` → `hf_focus_without_raise`; `.focusAndRaise` → set `kAXFrontmostAttribute` true on the app's
    `AXUIElementCreateApplication(pid)` and `AXRaise` on the cached window element (public AX calls; not
    `NSRunningApplication.activate()`, whose cooperative activation from an accessory app is unproven). A failed focus call is logged once per window (os_log, subsystem
    `com.wilddog64.hoverfocus`) and never retried in a loop.
16. `isPaused` true stops decisions without removing the tap; `apply(_:)` calls `Engine.update`; `stop()` removes the
    tap and timer, sets `isRunning` false, and is safe to call twice.

**Self-test (`Sources/hoverfocus-selftest/`):**

17. A small assert helper (`check(_ cond:, _ name:)`) counts passes and failures, prints one line per failure and a
    final `selftest: <p> passed, <f> failed`; exit 1 on any failure. Tests cover items 1–7 with synthetic samples and
    temp files (under the system temp dir), items 8–11 through the C entry points (the override, NULL guards and
    `pid <= 0`), and item 13 with stub `StartChecks` whose closures record that they were called, plus the engine
    trap cases of item 2 (tick earlier than start, `dwellMs: -1`). The self-test imports `CSkyLight`; if SwiftPM does
    not expose it through `HoverFocusPlatform`, stop and report. The self-test may name the private symbols only as
    string literals. The self-test never invokes the `liveChecks` closures (a trial tap can raise a permission prompt).
18. The SkyLight check (`hf_skylight_resolve().available == true`) runs by default, so the existing CI step
    `swift run hoverfocus-selftest` on `macos-26` catches a runner image whose macOS dropped a symbol. `HOVERFOCUS_SELFTEST_SKIP_SKYLIGHT=1`
    skips every assert that needs a healthy resolve (item 8 availability, item 11 override and the later-resolve
    check) and prints `skylight: skipped`; the NULL and `pid <= 0` guard tests still run.

**Docs:** `docs/config.md` changes the `dwellMs` range (line 12) to `0`–`5000` and the `stillnessPx` range (line 19)
to `0`–`200`, and states that the app rejects unknown keys, wrong types and out-of-range values (naming the key in the
menu status line). `README.md`: add bullets to the existing `## Known Limitations` section (line 89; do not add a
second heading): self-raising apps; same-app and non-key windows until live-checked.

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
| `docs/config.md`, `README.md` | the doc changes above |

`Sources/CSkyLight/include/CSkyLight.h` already declares every entry point; no change. Ownership of
`Sources/hoverfocus/MenuModel.swift`, `docs/config.md` and `README.md` passes from M1b (landed) to this task.

## Contract readers

- `Interface.swift` public names: reader `Sources/hoverfocus/**` (AppDelegate, MenuModel, main.swift). This spec
  changes none.
- `~/.config/hoverfocus/config.json` (or `HOVERFOCUS_CONFIG`): reader `ConfigLoader` (after this spec the only parser;
  `MenuModel.loadConfig` delegates), reached from `main.swift:12` (`--print-status`) and `main.swift:44`
  (`--print-config`, whose rc 2 now also fires on unknown keys and wrong types) and `AppDelegate.loadConfiguration`.
  Writers: the operator, and `AppDelegate.openConfig` (lines 242–249), which writes `Config()` with `JSONEncoder` only
  when the file is missing (menu toggles are memory-only), so an encoded default `Config` must load back.
  `config.example.json` must load without error. A new key is a change to `Config`, `ConfigLoader` and
  `docs/config.md`.
- `HoverFocusController.liveChecks`: readers `main.swift:24` and `AppDelegate.swift:31`; this spec makes it real.
- os_log subsystem `com.wilddog64.hoverfocus`: reader README ("how to see logs"). Writer this spec.
- `HOVERFOCUS_SELFTEST_SKIP_SKYLIGHT`: new; reader the self-test only.

## What NOT to Do

- No edit to `Package.swift`, `Interface.swift`, `CSkyLight.h` or any file outside the table. No new dependency.
- No code copied from AutoRaise, yabai or any other project; read for the method only.
- No `SLPSPostEventRecordTo`, no synthetic event records, no `kCPSUserGenerated`.
- No `sudo`, no `launchctl`, no writes outside the worktree and the system temp dir.
- No `fatalError`, `precondition` or force-unwrap on any path that depends on the system (permissions, symbols,
  AX results, file contents). No unchecked `UInt64` subtraction or `UInt64(Int)` conversion of config values.
- Do not run the app (the event tap needs Accessibility trust, which only the operator grants; live evidence), except
  `.build/debug/hoverfocus --print-config` with `HOVERFOCUS_CONFIG` pointing at a temp file
  (it reads the config and exits; it creates no tap).

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
    text: "ConfigLoader: missing file gives defaults; partial file fills defaults; non-JSON, top-level array, wrong type, unknown key, unknown pauseModifier or menuBarIcon value, dwellMs 5001 or -1, stillnessPx 201 give ConfigError.invalid naming the key (non-JSON and top-level array: a reason saying so); unreadable gives ConfigError.unreadable; a Config written by JSONEncoder loads back equal"
  - id: M6
    text: "hf_skylight_resolve returns available=true with missing_symbol NULL on this Mac and, with one symbol overridden to a bad name, available=false naming that symbol (pointer into the shim's table), while a later hf_skylight_resolve still returns available=true; hf_ax_window_id returns non-zero for a NULL element or out pointer and hf_focus_without_raise(-1, 0) returns non-zero, neither calling through; the resolve-failed early returns are shown by code reading"
  - id: M7
    text: "HoverFocusController.start throws (never crashes) for each failed precondition, checked in order: accessibilityNotTrusted, privateAPIUnavailable(symbol:), eventTapFailed; later checks are not evaluated after the first failure; isRunning stays false"
  - id: M9
    text: "the engine never traps: a tick whose nowMs is earlier than the candidate start yields .none, and Config(dwellMs: -1) behaves as dwellMs 0"
  - id: M8
    text: "MenuModel.loadConfig returns exactly what ConfigLoader.load returns, and throws what it throws, for the same file (proved through hoverfocus --print-config)"
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
    proves: [M1, M2, M3, M4, M5, M6, M8, M9, N1, N2, N4, N6]
    kind: offline
    command: "swift build && swift run hoverfocus-selftest, rc 0, final line 'selftest: <p> passed, 0 failed'. Then, with temp files: HOVERFOCUS_CONFIG=<unknown-key file> .build/debug/hoverfocus --print-config gives rc 2 naming the key on stderr; HOVERFOCUS_CONFIG=<partial file> gives rc 0 with defaults filled; HOVERFOCUS_CONFIG=config.example.json gives rc 0. Red controls, each restored byte-identical (git diff --stat empty after): engine mutant 'fire regardless of elapsed time' turns M1/N4 tests red; removing the fired latch turns the N4 fires-twice test red; removing the buttonsDown gate turns N2 red; returning .focusAndRaise for every target turns N1 red; dropping the unknown-key check turns M5 red; restoring the whole m1-base MenuModel.swift (with PartialConfig) makes the unknown-key --print-config give rc 0 (N6 red); replacing the saturating elapsed-time difference with plain subtraction makes the M9 test trap"
    intent: "The rules that decide when a window gets focus (wait time, drags, the pause key, menus, ignore and raise lists, the config file) are tested without needing your screen."
  - id: E2
    proves: [N3, N5, M6]
    kind: offline
    command: "git grep -nE '_SLPS|SLPS|SLS[A-Z]|GetProcessForPID|_AXUIElementGetWindow' -- Sources ':!Sources/CSkyLight' ':!Sources/hoverfocus-selftest' prints nothing, and under Sources/hoverfocus-selftest the names appear only inside string literals; git grep -nE 'PostEventRecord|UserGenerated|0x200([^0-9A-Fa-f]|$)' -- Sources prints nothing (no -w: it would miss SLPSPostEventRecordTo and kCPSUserGenerated) (comments must not cite variant A's flag value); the three symbols appear under Sources/CSkyLight only as string literals in the symbol table; otool -L on .build/debug/hoverfocus-selftest and .build/debug/hoverfocus lists no SkyLight; red controls: an extern declaration of _SLPSSetFrontProcessWithOptions added to a Platform file is found by the first grep; a dlsym of SLPSPostEventRecordTo added to CSkyLight.c is found by the second"
    intent: "The fragile private macOS calls live in one small file and are looked up at runtime, so a macOS update that removes them disables the tool instead of crashing it."
  - id: E3
    proves: [M7]
    kind: offline
    command: "selftest builds HoverFocusController with stub StartChecks for each of the three failure cases (and the all-pass-but-tap case is not run, since it would create a real tap); each start() throws the expected error, the process keeps running, isRunning stays false, and the recording stubs show later checks were not called; red control: swapping the first two checks in start() turns the order test red; code reading: liveChecks wires AX trust, the shim's missing_symbol and a trial tap, and start() returns early when isRunning"
    intent: "Without your permission granted, the tool refuses to start and says why, rather than crashing."
  - id: E-L1
    proves: [M1]
    kind: live
    command: "operator on m2-air after land and make install: parent E-L1 to E-L4 (grant Accessibility; 1. hover TextEdit behind Terminal, typing goes to TextEdit and it stays behind; 2. the menu shows Running, not eventTapFailed, with only Accessibility granted; 3. two TextEdit windows: hover the back one, typing goes to it, record whether it raised)"
    intent: "On your Mac, typing goes to the window under the pointer without that window jumping to the front."
interface: "Interface.swift and CSkyLight.h unchanged; Engine.update(_:) added; MenuModel.loadConfig behaviour now equals ConfigLoader.load; env HOVERFOCUS_SELFTEST_SKIP_SKYLIGHT (selftest only)"
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each mutant's red result and `git diff --stat` after restoring it.
- Run SwiftPM with `--disable-sandbox` if your environment refuses nested sandboxes (`sandbox_apply: Operation not
  permitted`); say so in the report.
