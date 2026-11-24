# hoverfocus v0.0.2 L1 — reload fails closed; watch Accessibility trust without a menu click

**Status:** spec rev 2 — Fable reviewed rev 1 (NEEDS FIXES: 1 blocker, 3 should-fix, 4 nits; all applied, Claude
verified the blocker); not dispatched (operator intent approval and go)
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.2-bug-batches.md`](hoverfocus-v0.0.2-bug-batches.md) (batch L1)
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.2` (cut from `main` at `d426f18`, tag `v0.0.1`)
**Risk:** low (app logic only; no install, no private API change)
**Implementer:** Luna (`agy`, logic). Runs in parallel with F1 (no shared file). **Verifier:** Claude, from
`## Acceptance` only.
**Filed:** 2026-11-23
**Intent approved:** operator, 2026-11-24
**Approval:** operator 2026-11-23 ("plan for bugs distributions between flash and luna"; "ship v0.0.1 and fix bugs in
v0.0.2")

## Fixes

| Input | Defect (v0.0.1) |
|---|---|
| Argon #1 (`docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md`) | `AppDelegate.reloadConfig()` (`AppDelegate.swift:229-236`): an invalid `config.json` sets `config = Config()` (defaults, `enabled: true`) and still calls `controller.apply(config)`; a running controller keeps focusing with defaults while the menu shows the config error (fails open) |
| B3 part 3 (`docs/hoverfocus/bugs/2026-11-23-hoverfocus-install-launchagent-and-tcc-grant-gaps.md`) | trust is polled only after the **Grant Accessibility…** menu click (`AppDelegate.swift:208-226`, 2 s × 60). Granting in System Settings directly leaves the app untrusted until restart |

## Before You Start

1. `git log --oneline -1` shows `d426f18`; `swift build` and `swift run hoverfocus-selftest` pass.
2. Read `Sources/HoverFocusCore/Interface.swift` (`FocusControlling`, `Config`, `ConfigError`, `ControllerError`),
   `Sources/hoverfocus/AppDelegate.swift` and `Sources/hoverfocus-selftest/main.swift`.
3. Do not edit `Interface.swift`, `Package.swift`, `Controller.swift`, `CSkyLight/*`, `MenuModel.swift`, `main.swift`
   (app) or any file outside `## Files`.

## Behaviour

The `hoverfocus` executable target cannot be imported by the selftest, so the lifecycle decisions move into a plain
`@MainActor` class in `HoverFocusCore` that the selftest drives with a fake controller. `AppDelegate` keeps only
AppKit work (menu, icon, timers) and calls the coordinator.

1. **New `Sources/HoverFocusCore/AppCoordinator.swift`:**

   ```swift
   @MainActor
   public final class AppCoordinator {
       public private(set) var config: Config          // last valid config (Config() before any valid load)
       public private(set) var configError: ConfigError?
       public private(set) var startError: ControllerError?
       public private(set) var watchingTrust: Bool
       public init(controller: any FocusControlling, isTrusted: @escaping @MainActor () -> Bool)
       public func load(_ result: Result<Config, ConfigError>)   // launch and Reload Config
       public func trustTick()                                    // called every 2 s while watchingTrust
       public func update(_ change: (inout Config) -> Void)       // Enabled toggle, icon style
   }
   ```

   - `load(.failure(e))`: `configError = e`; `controller.stop()`; `config` unchanged (the last valid one, so the menu
     checkmarks stay meaningful); **no** `apply`, **no** `start`. Then `watchingTrust = !isTrusted()`.
   - `load(.success(c))`: `config = c`, `configError = nil`, `controller.apply(c)`, then `tryStart()`. Then
     `watchingTrust = !isTrusted() || startError == .accessibilityNotTrusted` (covers trust flipping between the two
     reads; Fable 7).
   - `tryStart()` (private): `try controller.start()`; on success `startError = nil`; on a thrown `ControllerError`
     store it in `startError`; any other error (`start()` throws untyped, `Interface.swift:114`) maps to
     `.eventTapFailed`. Never throws.
   - `trustTick()`: if `!watchingTrust` return. If `isTrusted()`: `watchingTrust = false`; if `configError == nil`
     and `!controller.isRunning`, `tryStart()`. Otherwise keep watching. **No attempt cap.**
   - `update`: applies the change to `config`, then `controller.apply(config)`. Does not start or stop.
   - A valid config with `enabled: false` is not an error: it is applied and `start()` is still called (the engine
     stops focus for it, `Engine.swift:21`), exactly as in v0.0.1.

2. **`AppDelegate.swift`:**
   - Owns `coordinator = AppCoordinator(controller: controller, isTrusted: { AccessibilityPermission.isTrusted(prompt: false) })`.
     `config` and `configError` reads go through the coordinator; the private copies are removed.
   - Launch and **Reload Config** build a `Result<Config, ConfigError>` from `MenuModel.loadConfig()` (a non-
     `ConfigError` maps to `.invalid(path: MenuModel.configPath(), reason: error.localizedDescription)` as today) and
     call `coordinator.load(_:)`.
   - **Enabled** and **Menu Bar Icon** call `coordinator.update { ... }`.
   - After every coordinator call, `syncTrustTimer()`: if `coordinator.watchingTrust` and no timer, schedule one
     repeating 2 s timer whose closure hops to the main actor with the existing `Task { @MainActor in … }` pattern
     (`AppDelegate.swift:213`) and calls `coordinator.trustTick()`, then `syncTrustTimer()` and `updateUI()`; if not
     watching, invalidate it. One timer at most. `accessibilityAttempts` and the 60-attempt cap are removed.
   - **Grant Accessibility…** calls `AccessibilityPermission.isTrusted(prompt: true)` and `syncTrustTimer()` (the
     watch is already on while untrusted; it no longer has its own timer).
   - `updateUI()` status precedence: `configError` → `Error: config <reason>`; else `!config.enabled` → `Off`; else
     paused → `Paused`; else running → `Running`; else `startError` → its status line. (v0.0.1 had no `startError`
     branch and relied on `startController()` writing the title.)
   - No other behaviour changes (pause timer, Open Config, Quit, icon, single instance, CLI flags).

3. **Selftest (`Sources/hoverfocus-selftest/main.swift`):** add a `FakeController: FocusControlling` that records
   calls in order (`apply(<dwellMs>)`, `start`, `stop`), recording `start` on **every** call, including calls that
   throw or no-op; keeps `isRunning` (`start` when running is a no-op, as in `HoverFocusController`), and throws a
   settable `ControllerError?` from `start`. A settable `trusted` flag feeds
   `isTrusted`. Cases, each a named `check`:
   - **A1 fails closed:** load valid `Config(dwellMs: 200)` (trusted) → running; then `load(.failure(.invalid(...)))`
     → `stop` recorded, `isRunning == false`, no `apply` after the failure, `config.dwellMs == 200`, `configError`
     set.
   - **A1 recovers:** then load valid `Config(dwellMs: 300)` → `apply(300)` then `start`, running, `configError` nil.
   - **Positive control:** valid `Config(enabled: false)` → `apply` and `start` both recorded, `configError` nil.
   - **Watch without a click:** untrusted, fake `start` throws `.accessibilityNotTrusted`; load valid → `startError ==
     .accessibilityNotTrusted`, `watchingTrust`; 100 × `trustTick()` while untrusted → still watching, no extra
     `start`; set trusted, clear the throw, one `trustTick()` → exactly one more `start`, running, `watchingTrust`
     false, `startError` nil.
   - **Config error stays closed:** untrusted + `load(.failure)`; grant; `trustTick()` → no `start`, watching false.
   - **Trusted at launch:** trusted load → `watchingTrust == false`.

## Files

| File | Change |
|---|---|
| `Sources/HoverFocusCore/AppCoordinator.swift` | new |
| `Sources/hoverfocus/AppDelegate.swift` | route lifecycle through the coordinator; one trust timer |
| `Sources/hoverfocus-selftest/main.swift` | add the fake controller and the cases above |

## Contract readers

- `FocusControlling` (`Interface.swift:110-117`): unchanged; new readers `AppCoordinator` and the selftest fake.
- `MenuModel.statusLine(for:)` (`MenuModel.swift`): unchanged; `AppDelegate.updateUI` gains a `ControllerError` branch.
- README "Granting Accessibility" text and `docs/config.md:6` ("keeps the defaults, reports the error … and continues
  running", false after this change) are F1's files; F1 updates both (Fable 2).

## External behaviour (proof)

The trust watch assumes `AXIsProcessTrusted()` turns true inside an already running process after a grant in System
Settings, and that `CGEvent.tapCreate` then succeeds without a relaunch. Not yet observed: the B3 doc records only
reset + re-grant + kickstart. **L1-EL is the proof and gates the merge of `v0.0.2`** (Fable 3); if the grant is not
seen without a relaunch, L1's trust watch is replaced by a documented kickstart step before merge.

## What NOT to Do

- No edit outside `## Files`. No new dependency, no distributed-notification observer (polling is the chosen
  mechanism: provable offline and cheap at 2 s).
- Do not launch the app with a window server session; use `swift run hoverfocus-selftest` and the CLI flags.
- Run every command under
  `sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/sudo") (literal "/bin/launchctl"))'`.

## Acceptance

```yaml
must:
  - id: L1-M1
    text: "AppCoordinator.load(.failure) stops the controller, does not apply or start, keeps the last valid config and sets configError; a later valid load applies it and starts"
  - id: L1-M2
    text: "while untrusted, watchingTrust stays true with no attempt cap; the first trustTick after trust is granted starts the controller exactly once and stops watching, with no menu action"
  - id: L1-M3
    text: "AppDelegate calls controller start/stop/apply only through AppCoordinator; at most one 2 s trust timer exists and runs exactly while coordinator.watchingTrust; the 60-attempt cap is gone; updateUI shows startError's status line when not running"
must_not:
  - id: L1-N1
    text: "an invalid config reload leaves the controller running with defaults applied (paired: a valid enabled:false config still applies and starts)"
  - id: L1-N2
    text: "trust granted in System Settings goes unnoticed until restart or a menu click (paired: trust already granted at load does not watch)"
  - id: L1-N3
    text: "trust granted while a config error is showing starts the controller (paired: the same grant with a valid config starts it)"
evidence:
  - id: L1-E1
    proves: [L1-M1, L1-N1]
    kind: offline
    command: "swift build; swift run hoverfocus-selftest rc 0 with the A1 fails-closed, A1 recovers and positive-control checks named in the output or counted. Red control, restored byte-identical: make load(.failure) set config = Config() and call controller.apply(config) without stop (the v0.0.1 behaviour) — the fails-closed checks fail, the positive control still passes"
    intent: "A broken config file stops focus-follows-mouse instead of quietly running with default settings; fixing the file and reloading starts it again."
  - id: L1-E2
    proves: [L1-M2, L1-N2, L1-N3]
    kind: offline
    command: "same selftest run: watch-without-a-click, config-error-stays-closed and trusted-at-launch checks pass. Red controls, each restored byte-identical: (a) do not set watchingTrust in load — watch-without-a-click fails; (a2) set watchingTrust = true always in load — trusted-at-launch fails; (b) stop watching after 60 ticks — the 100-tick check fails; (c) drop the configError guard in trustTick — config-error-stays-closed fails"
    intent: "Granting Accessibility permission in System Settings starts the app within about 2 seconds, with no menu click and no time limit, but not while a config error is showing."
  - id: L1-E3
    proves: [L1-M3]
    kind: offline
    command: "git grep -nE 'controller\\.(start|stop|apply)\\(' -- Sources/hoverfocus/AppDelegate.swift prints nothing (main.swift's --print-status path keeps its own controller calls and is out of scope); git grep -n 'accessibilityAttempts' -- Sources prints nothing; code reading of syncTrustTimer and updateUI against Behaviour 2, quoted with line numbers"
    intent: "Only one piece of code starts and stops the app, so the menu, permission and reload paths cannot disagree about whether it is running."
  - id: L1-EL
    proves: [L1-M2, L1-M1]
    kind: live
    command: "operator on m2 (home): install v0.0.2 build, tccutil reset Accessibility com.wilddog64.hoverfocus, start the app (menu: Needs Accessibility permission), grant in System Settings without touching the menu — within ~4 s the menu shows Running and hover focus works; then break config.json, Reload Config — menu shows Error: config and hovering no longer focuses; fix it, Reload — Running again"
    intent: "On m2, after resetting the permission, granting it in System Settings without touching the menu switches the menu to Running and hover focus starts within about 4 seconds."
interface: "adds public AppCoordinator in HoverFocusCore; no change to Interface.swift, CLI flags or config keys"
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each red control's failing output and `git diff --stat` after restoring it. Commit nothing; Claude lands.
