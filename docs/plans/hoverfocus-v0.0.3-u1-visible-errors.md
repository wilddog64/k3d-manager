# hoverfocus v0.0.3 U1 — visible errors: red status line, one notification per error, Accessibility loss detected

**Status:** spec rev 3 — Argon reviewed rev 1 (2026-11-25, NEEDS FIXES: 4 should-fix, 1 nit; all applied); Neon blind
review of rev 1 (2026-11-25, NEEDS FIXES: 4 blockers, 5 should-fix, 2 nits; all applied, incl. a stuck-Running state
confirmed in `AppCoordinator.swift:29-35`); not dispatched
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.3-plan.md`](hoverfocus-v0.0.3-plan.md) (batch U1)
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.3` **after L3 lands** (both edit
`Sources/hoverfocus-selftest/main.swift`; one dispatch per file)
**Risk:** low (menu and notification UI; one lifecycle change in `AppCoordinator.trustTick`)
**Implementer:** Luna (`codex`, `gpt-6-luna`, logic). **Verifier:** Claude, from `## Acceptance` only.
**Filed:** 2026-11-25
**Intent approved:** pending
**Approval:** `docs/ideas.md` row 2026-11-24 (operator UX note during L1-EL: "the grey disabled status line is hard to
read"), taken into v0.0.3 by the plan approved 2026-11-24; operator 2026-11-25 "go ahead to do 1 .. 3"

## Fixes

| Input | Defect (v0.0.2, `d2cdb00`) |
|---|---|
| Idea 2026-11-24 | An error shows only as a grey, disabled first menu line (`AppDelegate.swift:51-52`); nothing tells the user unless they open the menu |
| Plan U1 "Accessibility lost" | Once running, trust is never re-checked: `AppCoordinator.trustTick` returns at once when `!watchingTrust` (`AppCoordinator.swift`), and the 2 s timer only runs while watching. A revoked grant leaves the menu saying `Running` while nothing focuses |

## External behaviour (proof)

- **Notifications need a bundle.** `UNUserNotificationCenter.current()` raises an exception in a process with no app
  bundle (Apple documents the bundle requirement; seen in practice as `bundleProxyForCurrentProcess is nil`). The
  `hoverfocus` binary also runs unbundled (`swift run`, `--print-status`), so every notification call is guarded by
  `Bundle.main.bundleURL.pathExtension == "app"`.
- **Notification permission is per signing identity** like other TCC grants; ad-hoc builds may re-prompt after each
  install. F2's stable identity removes that; the U1 live check runs on an identity-signed build.
- **Not yet observed:** whether `AXIsProcessTrusted()` turns false inside a running process when the grant is removed
  in System Settings (the reverse of L1-EL, which proved grant-while-running). U1-EL is the proof; if it does not turn
  false, the loss branch is inert (never fires) but harmless, and the README says a revoked grant needs a relaunch.
- **Not yet observed:** an enabled `NSMenuItem` with an `attributedTitle` foreground colour renders in that colour in a
  status-bar menu on macOS 26. U1-EL checks it by sight; disabled items are drawn grey by AppKit, which is why the error
  line becomes enabled (Behaviour 3).

## Before You Start

1. `git log --oneline -1` shows the `v0.0.3` head with L3 landed; `swift build --disable-sandbox` and
   `swift run --disable-sandbox hoverfocus-selftest` pass. Every `swift` command carries `--disable-sandbox` and runs
   with `CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-mc"` (the worker sandbox denies writes to `~/.cache/clang`).
2. Read `Sources/HoverFocusCore/AppCoordinator.swift`, `Sources/hoverfocus/AppDelegate.swift`,
   `Sources/hoverfocus/MenuModel.swift` (its `AppStatus` and `statusLine` functions) and the L1 rows in
   `Sources/hoverfocus-selftest/main.swift` (`FakeController`).
3. Do not edit `Interface.swift`, `Package.swift`, `Controller.swift`, `CSkyLight/*`, `MenuModel.swift`, app
   `main.swift`, or any file outside `## Files`.

## Behaviour

1. **New `Sources/HoverFocusCore/Health.swift`** (pure, testable):

   ```swift
   public enum Health: Equatable, Sendable {
       case ok                                  // running, off, paused or starting: nothing to report
       case configError(ConfigError)
       case startError(ControllerError)
   }
   public struct ErrorNotifier {
       public init()
       /// Returns the error to announce when `health` is an error that differs from the last observed value;
       /// nil when ok, or when the same error is still present.
       public mutating func observe(_ health: Health) -> Health?
   }
   ```

   `ok → configError(a)` announces; `configError(a)` again → nil; `configError(a) → configError(b)` (different reason)
   announces; `configError(b) → startError(.accessibilityNotTrusted)` announces; `→ startError(.eventTapFailed)`
   announces; `startError(.eventTapFailed)` again → nil; `→ ok` → nil; then `startError(.eventTapFailed)` (the **same** error as
   before `ok`) announces again. Comparison is
   full `Equatable` equality of `Health`, including associated values.

2. **`AppCoordinator`:**
   - `public var health: Health`, with v0.0.2's `updateUI` precedence: `configError` if set; else `.ok` if
     `!config.enabled` or `controller.isPaused`; else `startError` if set and the controller is not running; else `.ok`.
     (Off and Paused never show red and never notify, even with a stored start error.)
   - `trustTick()` gains a loss branch, checked first and **not** gated on `watchingTrust`: if the controller is
     running and `!isTrusted()` → `controller.stop()`, `startError = .accessibilityNotTrusted`, `watchingTrust = true`,
     return. Then the existing `guard watchingTrust` path runs unchanged (re-grant restarts it). Not gating matters:
     `load(.success)` while running and untrusted leaves `watchingTrust == true` with the controller still running
     (`start()` is a no-op when running, `AppCoordinator.swift:29`, `Controller.swift:46`), and a gated branch would
     never fire.
3. **`AppDelegate`:**
   - The single repeating 2 s timer is created once in `applicationDidFinishLaunching` (guarded by
     `accessibilityTimer == nil`) and runs for the app's lifetime; each tick calls `coordinator.trustTick()` then
     `updateUI()`. `syncTrustTimer()` and every call to it (`loadConfiguration`, `toggleEnabled`, `selectIconStyle`,
     `grantAccessibility`) are removed. The second `updateUI()` in `applicationDidFinishLaunching` may stay (the
     notifier deduplicates it).
   - `updateUI()` computes `coordinator.health`. On an error: `statusMenuItem.attributedTitle` = the existing
     `MenuModel.statusLine` text with `.foregroundColor: NSColor.systemRed` and `.font: NSFont.menuFont(ofSize: 0)`;
     `target = self`, `isEnabled = true`, and `action`: `configError` → `openConfig`,
     `startError(.accessibilityNotTrusted)` → `grantAccessibility`, other start errors → `reloadConfig`. On `.ok`:
     `attributedTitle = nil` first, then the plain `title`, `target = nil`, `action = nil`, `isEnabled = false` (today's look).
   - `AppDelegate` holds `private var errorNotifier = ErrorNotifier()` (a stored property, never a local).
     `updateUI()` passes `health` to it; when it returns an error and the bundle guard holds, one helper
     `postErrorNotification(body:)` starts `Task { @MainActor in … }` that does
     `try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])` and, if that returns true,
     `try? await center.add(request)` (identifier `UUID().uuidString`, title `HoverFocus`, body = the status line).
     It requests on every announcement (macOS prompts only while `.notDetermined` and otherwise answers at once from
     the stored setting; no "already asked" flag). No `UNUserNotificationCenterDelegate` is added (a banner may be
     suppressed while the app is frontmost; HoverFocus is an accessory app, so this is accepted). Denied or
     unavailable: nothing more (the red line remains).
   - "No authorization request at launch" means no eager request when healthy: a launch that lands in an error
     (broken config, no grant) announces and requests like any other transition.
   - Log with `Logger(subsystem: "com.wilddog64.hoverfocus", category: "health")`, `privacy: .public`: each announced
     transition (`health <case>`), the loss branch firing (`trust lost`), and the notification outcome
     (`notify granted=<bool> posted=<bool>`).
4. **Selftest:** named `check` rows, each with a fresh coordinator and `FakeController` (reuse L1's):
   - **Notifier:** the transition table in Behaviour 1, as one row per arrow.
   - **Loss detected:** trusted, valid load → running; set untrusted; `trustTick()` → `stop` recorded, not running,
     `startError == .accessibilityNotTrusted`, `watchingTrust`, `health == .startError(.accessibilityNotTrusted)`.
   - **Loss recovers:** repeat the loss setup on its fresh coordinator, then trusted + one `trustTick()` → one more
     `start`, running, `health == .ok`.
   - **Reload while lost:** trusted, valid load → running; set untrusted; valid `load(.success)` (fake `start` is a
     no-op while running) → `watchingTrust` true and still running; one `trustTick()` → `stop` recorded,
     `health == .startError(.accessibilityNotTrusted)`.
   - **Off/Paused stay quiet:** untrusted, fake `start` throws `.accessibilityNotTrusted`, load valid
     `Config(enabled: false)` → `health == .ok`; same with `enabled: true` and `isPaused = true` → `.ok`.
   - **No false loss (positive control):** trusted, running; 100 × `trustTick()` → no `stop`, no extra `start`.
   - **Health precedence:** config error and a start error together → `configError`; start error while the fake
     reports running → `.ok` (set up by a failed load, then clearing the fake's throw and calling `try? fake.start()`).
   - Existing L1 rows keep passing unchanged.

## Files

| File | Change |
|---|---|
| `Sources/HoverFocusCore/Health.swift` | new |
| `Sources/HoverFocusCore/AppCoordinator.swift` | `health`; loss branch in `trustTick` |
| `Sources/hoverfocus/AppDelegate.swift` | lifetime timer; red enabled error line; notifier and notification |
| `Sources/hoverfocus-selftest/main.swift` | rows above |

## Contract readers

- `AppCoordinator.trustTick` / `watchingTrust` (L1): readers `AppDelegate` (timer) and the L1 selftest rows; L1-M2
  ("no attempt cap; first tick after grant starts exactly once") still holds and its rows must stay green.
- `MenuModel.statusLine(for:)`: read, unchanged; now also the notification body.
- README "Menu Bar Interface" (`README.md:73-89`) lists the status strings; the README is F2's file in this release,
  so Claude adds the red clickable error line and the notification there at release (noted in the parent plan), not
  the worker.

## What NOT to Do

- No edit outside `## Files`. No notification while an error persists; no notification for Off or Paused.
- No `UNUserNotificationCenter` call outside the bundle guard; no authorization request at launch.
- Do not launch the app against the window server; use `swift run --disable-sandbox hoverfocus-selftest`.
- Run every command under
  `sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/sudo") (literal "/bin/launchctl"))'`.

## Acceptance

```yaml
must:
  - id: U1-M1
    text: "ErrorNotifier announces exactly on a transition into an error or into a different error, never while the same error persists, and again after a return to ok"
  - id: U1-M2
    text: "while running, a trustTick that finds Accessibility no longer trusted stops the controller, sets startError accessibilityNotTrusted and starts watching; a later grant restarts it once"
  - id: U1-M3
    text: "AppDelegate shows an error status line in systemRed as an enabled item with the action for that error, posts one notification per ErrorNotifier announcement behind a bundle guard with authorization requested on first need, and runs one lifetime 2 s timer"
must_not:
  - id: U1-N1
    text: "a persisting error posts a notification on every UI update (paired: a new, different error does post)"
  - id: U1-N2
    text: "a revoked Accessibility grant leaves the controller marked running with no error shown (paired: a trusted running controller is never stopped by trustTick)"
evidence:
  - id: U1-E1
    proves: [U1-M1, U1-N1]
    kind: offline
    command: "swift build --disable-sandbox; swift run --disable-sandbox hoverfocus-selftest rc 0 with every notifier row passing. Red controls, each restored byte-identical: (a) announce on every error observation — the same-error row fails; (b) compare only the case, not the associated value — the different-reason row fails; (c) never reset on ok — the same-error-after-ok row fails"
    intent: "You get one notification when HoverFocus breaks (bad config, permission lost, event tap failure), not a stream of them while it stays broken, and a new one if it breaks again later."
  - id: U1-E2
    proves: [U1-M2, U1-N2]
    kind: offline
    command: "same run: loss detected, loss recovers, no false loss, health precedence and all L1 rows pass. Red controls, restored: (a) delete the loss branch — loss-detected fails; (b) drop the isTrusted check in the loss branch — no-false-loss fails; (c) gate the loss branch on !watchingTrust — reload-while-lost fails; (d) put startError before the Off/Paused check in health — off/paused-stay-quiet fails"
    intent: "If the Accessibility permission is removed while HoverFocus runs, the menu stops saying Running and shows the error; granting it again resumes focus."
  - id: U1-E3
    proves: [U1-M3]
    kind: offline
    command: "git grep -n 'UNUserNotificationCenter' -- Sources/hoverfocus/AppDelegate.swift: every line is inside postErrorNotification, which is only called behind the bundle guard (quote both); the stored errorNotifier declaration and the statusMenuItem target/action/isEnabled lines quoted; git grep -n 'systemRed' -- Sources/hoverfocus/AppDelegate.swift prints at least one line; git grep -n 'syncTrustTimer' -- Sources prints nothing; code reading of updateUI and the timer setup quoted with line numbers against Behaviour 3"
    intent: "The error line is red and clickable, notifications only happen in the installed app, and there is a single background check."
  - id: U1-EL
    proves: [U1-M1, U1-M2, U1-M3]
    kind: live
    command: "operator on m2, identity-signed v0.0.3 build with U1: (1) break config.json, Reload Config — one notification 'HoverFocus' with the config error (allow notifications at the first prompt), the menu's first line is red and opens the config when clicked; Reload twice more — no further notification; fix and Reload — line back to Running, plain. (2) Remove HoverFocus from System Settings > Accessibility while running — within ~4 s the line turns red (Needs Accessibility permission) and one notification arrives; re-add — Running again. Claude reads the unified log over SSH. If step 2 shows no change, record that AXIsProcessTrusted did not flip in-process (External behaviour) and file the README note"
    intent: "On m2, a broken config or a removed permission turns the menu line red and sends one notification, and fixing it brings HoverFocus back to Running."
interface: "HoverFocusCore adds public Health and ErrorNotifier and AppCoordinator.health; trustTick also detects lost trust; no change to Interface.swift, config keys or CLI flags."
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each red control's failing output and `git diff --stat` after restoring it. Commit nothing; Claude lands.
