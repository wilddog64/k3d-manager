# hoverfocus M1b — menu bar app, icon, bundle, install, CI, docs

**Status:** READY rev 2, 2026-11-22 — Fable reviewed rev 1 ("ready after fixes"); rev 2 applies findings 2, 4, 10–14,
17 and the operator's icon and menu bar choices (adjudication table at the end)
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release; no `docs/ideas.md` row.
**Parent:** [`hoverfocus-m1-prototype.md`](hoverfocus-m1-prototype.md) (design, facts, interface, file ownership)
**Repo / branch:** `wilddog64/hoverfocus` / task branch from `m1-base` at `92ab158` (interface commit plus
`Config.menuBarIcon`)
**Version:** v0.1.0
**Risk:** low (user-space app and user LaunchAgent; no sudo). The install target writes under `$HOME`; tests run it
only against a scratch root with `launchctl` stubbed.
**Implementer:** Flash (`agy`, `gemini-3.8-flash-medium`; shell, packaging, docs). Dispatched before M1a, which waits on
the operator's focus probe; no shared files. It builds against the interface stubs, so the app runs but does nothing
until M1a lands. **Verifier:** Claude (Sonnet verifier from `## Acceptance` only).
**Filed:** 2026-11-22
**Intent approved:** operator, 2026-11-22
**Intent note:** "your intents approved", for the evidence intent lines as written in rev 1; rev 2 keeps them verbatim
**Approval:** operator 2026-11-22 (see parent); M1b first, M1a after the probe: operator 2026-11-22 ("sounds good")

## Before You Start

1. `git log --oneline -2` shows `92ab158` on top of `007879f`; `swift build` succeeds; `swift --version` says 6.x.
2. Read the parent spec, then `Sources/HoverFocusCore/Interface.swift` and the stub
   `Sources/HoverFocusPlatform/Controller.swift`. Use only these public names: `Config` (all fields, including
   `menuBarIcon`), `MenuBarIconStyle`, `PauseModifier`, `ConfigError`, `ConfigLoader.load(from:)`, `ControllerError`,
   `FocusControlling`, `HoverFocusController(config:checks:)`, `HoverFocusController.liveChecks`, `StartChecks`,
   `AccessibilityPermission.isTrusted(prompt:)`. `FocusControlling` and `HoverFocusController` are `@MainActor`; call
   them from the main actor. Do not edit `Interface.swift`, `Controller.swift`, `Package.swift` or any other M1a file.
   If the interface cannot express something you need, stop and report.

## Behaviour

**App (`Sources/hoverfocus/`):**

1. An `NSApplication` with activation policy `.accessory` (no Dock icon) and an `NSStatusItem` menu:
   - status line (disabled item): `Running`, `Paused`, `Off`, `Needs Accessibility permission`,
     `Unavailable: <symbol>` (from `ControllerError.privateAPIUnavailable`), `Error: event tap` (from
     `.eventTapFailed`) or `Error: config <reason>`;
   - `Enabled` (checkmark; toggles `Config.enabled` in memory and calls `apply`);
   - `Pause for 30 minutes` / `Resume` (sets `isPaused`; a timer clears it);
   - `Menu Bar Icon` submenu: `Automatic`, `Colour`, `Light bar`, `Dark bar` (checkmark on the current
     `menuBarIcon`; applies at once, in memory only, like `Enabled`);
   - `Grant Accessibility…` (shown only when not trusted; calls `isTrusted(prompt: true)` and retries `start()` every
     2 s for up to 2 minutes);
   - `Reload Config`, `Open Config` (creates the file from `config.example.json`'s content if missing, then opens it
     with the default editor), `Quit`.
2. On launch: load `~/.config/hoverfocus/config.json` (`HOVERFOCUS_CONFIG` env var overrides the path). On
   `ConfigError`, keep defaults, show `Error: config <reason>` and do not crash. Then `start()`; each thrown
   `ControllerError` maps to its status line.
3. **Single instance:** on launch, if another running app has bundle id `com.wilddog64.hoverfocus` (other than this
   process), log one line and exit 0. Skipped for the CLI flags below.
4. **Menu bar icon (concept B "Dwell", operator 2026-11-22).** Drawn in code in an 18×18 pt image
   (`NSImage(size:flipped:drawingHandler:)`, flipped so the origin is top-left), coordinates in points:
   - window: rounded rect x 7.5, y 7.5, w 9, h 8, radius 1.5, filled with the glyph colour;
   - dwell track: circle centre (6, 6), radius 4.2, stroke 1.5, track colour;
   - dwell arc: the same circle, 40% of its length, starting at 12 o'clock, clockwise, round caps, arc colour;
   - pointer: filled circle centre (6, 6), radius 1.4, glyph colour.
   Colours by `menuBarIcon` and the status item button's effective appearance (dark bar = `.darkAqua` best match):

   | style | template | glyph | track | arc |
   |---|---|---|---|---|
   | `auto` | yes | black | black 25% | black |
   | `color`, light bar | no | #111111 | #111111 20% | #0B8F7C |
   | `color`, dark bar | no | #FFFFFF | #FFFFFF 25% | #4FD8BF |
   | `light` | no | #111111 | #111111 25% | #111111 |
   | `dark` | no | #FFFFFF | #FFFFFF 30% | #FFFFFF |

   Paused or Off: the whole image at 40% alpha in every style. The image is rebuilt when the style, the paused/enabled
   state or the button's `effectiveAppearance` changes (KVO). The table lives in `MenuModel.swift` as a pure function
   `iconColors(style:darkBar:dimmed:)` returning plain RGBA values and the template flag.
5. The config path, the status text mapping, the icon colour table and the menu model live in plain Swift types
   separate from AppKit (`MenuModel.swift`), so they run without a window server. CLI flags (each exits before any
   AppKit setup, no status item):
   - `--print-status`: load config, build `HoverFocusController(config:)` with `liveChecks`, try `start()`, print the
     status line, call `stop()`, exit 0.
   - `--print-status-table`: print one line per mapping, `<case> -> <status line>`, for every `ControllerError` case,
     both `ConfigError` cases (with a sample path and reason), `Running`, `Paused` and `Off`; then one line per
     `iconColors` row (`icon <style> dark=<bool> dimmed=<bool> template=<bool> glyph=<rgba> track=<rgba> arc=<rgba>`)
     for every style × dark × dimmed (16 rows); exit 0.
   - `--print-config`: load config (same path rules) and print the effective `Config` as JSON with sorted keys and
     every key present; on `ConfigError` print `Error: config <reason>` to stderr and exit 2.

**App icon (`packaging/`):**

6. `packaging/render_icon.swift` (run with `swift packaging/render_icon.swift <outdir>`) draws concept B with
   CoreGraphics into a bitmap context (no AppKit window, no window server) and writes the PNGs an `.iconset` needs
   (`icon_16x16.png` … `icon_512x512@2x.png`). Geometry on a 100×100 grid, origin top-left, scaled to each size:
   - background: rounded rect 0,0,100,100, radius 22.5, #EDF2EF;
   - back window: rounded rect x 14, y 18, w 52, h 44, radius 6, fill #FFFFFF, stroke #16302B width 2.4;
   - front window: rounded rect x 38, y 42, w 48, h 40, radius 6, fill #16302B;
   - dwell track: circle centre (29, 36), radius 10, stroke #C9D6D1 width 2.6;
   - dwell arc: same circle, 44 of its ~62.8 length from 12 o'clock clockwise, stroke #0E9F8A width 2.6, round caps;
   - pointer arrow: polygon (29,36) (29,51) (32.6,47.8) (35.3,53.8) (37.8,52.7) (35.2,46.9) (39.9,46.7), fill #16302B,
     stroke #FFFFFF width 1.2, round joins.
   `make icon` runs it into `build/AppIcon.iconset` and `iconutil -c icns` into `build/AppIcon.icns`.

**Bundle and install (`Makefile`, `packaging/`):**

7. `make build` → `swift build -c release`; `make selftest` → `swift run hoverfocus-selftest`; `make bundle` (depends
   on `icon`) → `build/HoverFocus.app` with `Contents/MacOS/hoverfocus`, `Contents/Resources/AppIcon.icns`,
   `Contents/Info.plist` (`CFBundleIdentifier` `com.wilddog64.hoverfocus`, `CFBundleExecutable` `hoverfocus`,
   `CFBundleIconFile` `AppIcon`, `LSUIElement` true, `CFBundleShortVersionString` 0.1.0, `LSMinimumSystemVersion` 14.0),
   signed with `codesign --force --sign "$(CODESIGN_IDENTITY)"` (`CODESIGN_IDENTITY` defaults to `-`, ad hoc).
8. `make install`: refuses (non-zero, before any write) if `APPDIR` or `AGENTDIR` is empty; `mkdir -p` both; copies the
   bundle to `$(APPDIR)/HoverFocus.app` (default `$(HOME)/Applications`) replacing any old copy; writes
   `$(AGENTDIR)/com.wilddog64.hoverfocus.plist` (default `$(HOME)/Library/LaunchAgents`) from
   `packaging/com.wilddog64.hoverfocus.plist.tmpl` (`Label`, `ProgramArguments` the installed binary, `RunAtLoad` true,
   `KeepAlive` `{SuccessfulExit: false}`, `LimitLoadToSessionType` `Aqua`); then
   `$(LAUNCHCTL) bootout gui/$$(id -u)/com.wilddog64.hoverfocus` (failure ignored: not loaded) followed by
   `$(LAUNCHCTL) bootstrap gui/$$(id -u) <plist>`, so running install twice works. `make uninstall`: same empty-variable
   refusal; bootout (ignore not loaded), remove the plist and the bundle. `LAUNCHCTL` defaults to `launchctl`. Neither
   target uses `sudo` or writes outside `APPDIR` and `AGENTDIR`.
9. `tests/install_test.sh` (`set -euo pipefail`):
   - builds the bundle first;
   - `root=$(mktemp -d)`, writes the marker file `$root/HF_TEST_ROOT`, sets `HOME=$root/home`, `APPDIR` and `AGENTDIR`
     under it, and puts a stub `launchctl` in `$root/bin` that exits 97 unless `$root/HF_TEST_ROOT` exists, otherwise
     appends its argv to `$root/launchctl.log`; `LAUNCHCTL` points at the stub and `$root/bin` leads `PATH`;
   - asserts `HOME` is under `$root` before running `make`;
   - snapshots the path list under `$root` (excluding the log), runs `make install` twice, then `make uninstall`, and
     checks: the bundle and plist exist after install; the plist has `LimitLoadToSessionType` `Aqua`
     (`plutil -extract`); the log holds `bootout gui/<uid>/com.wilddog64.hoverfocus` before each
     `bootstrap gui/<uid> <plist>`; after uninstall both are gone and the path list equals the snapshot;
   - `make install APPDIR=` exits non-zero and changes nothing;
   - checks the bundle's Info.plist keys (Behaviour 7) with `plutil -extract` and that `AppIcon.icns` exists;
   - removes `$root` on exit (trap).

**CI (`.github/workflows/ci.yml`):** on push and pull_request; one job with id and name `build`; runner `macos-26`;
`actions/checkout@v4`; `permissions: contents: read`; steps: `swift --version` (fail unless it reports 6.x),
`swift build`, `swift run hoverfocus-selftest`, `bash tests/install_test.sh`. (Fable 2: `macos-14` ships Swift 5.10,
which rejects `swift-tools-version: 6.0`.) The selftest's SkyLight check is M1a's; CI does not set
`HF_EXPECT_SKYLIGHT`.

**Docs:** `README.md` (what it does, build, install, granting Accessibility, the menu, the four menu bar icon styles,
logs with `log stream --predicate 'subsystem == "com.wilddog64.hoverfocus"'`, re-granting after a rebuild with
`tccutil reset Accessibility com.wilddog64.hoverfocus`, signing with `CODESIGN_IDENTITY`, known limits: private API
that can break on a macOS update, ad-hoc signing makes macOS ask for Accessibility again after each rebuild, Electron
and full-screen apps may behave differently, personal machines only), `docs/config.md` (every `Config` key, type,
default, range or allowed values), `config.example.json` (every key with its default, sorted keys, so it equals
`--print-config` output with no config file), `LICENSE` (MIT). Keep the existing `.gitignore`.

## Files

| File | Change |
|---|---|
| `Sources/hoverfocus/main.swift` | replace stub |
| `Sources/hoverfocus/*.swift` | new (app delegate, menu, `MenuModel.swift`, `MenuBarIcon.swift`) |
| `Makefile` | new |
| `packaging/Info.plist`, `packaging/com.wilddog64.hoverfocus.plist.tmpl`, `packaging/render_icon.swift` | new |
| `tests/install_test.sh` | new |
| `.github/workflows/ci.yml` | new |
| `README.md` | replace the stub |
| `docs/config.md`, `config.example.json`, `LICENSE` | new |

## Contract readers

- `Interface.swift` public names (reader: this spec; writer: Claude's interface commits `007879f`, `92ab158`; M1a keeps
  them).
- `~/.config/hoverfocus/config.json` and `HOVERFOCUS_CONFIG`: writer the operator; reader `ConfigLoader` (M1a) via
  this shell. `config.example.json`, `docs/config.md` and `--print-config` must match `Config`'s defaults in
  `Interface.swift`.
- LaunchAgent label `com.wilddog64.hoverfocus`, `~/Applications/HoverFocus.app`: writer `make install`; readers
  `make uninstall`, README.
- Bundle id `com.wilddog64.hoverfocus`: writer `packaging/Info.plist`; readers the single-instance check and the
  `tccutil` line in README.
- os_log subsystem `com.wilddog64.hoverfocus` (writer M1a): reader README.
- CI job name `build`: reader the `main` branch protection rule (Claude adds it as a required check after this lands).

## What NOT to Do

- No edit to `Package.swift`, `Interface.swift`, `.gitignore` or any file M1a owns. No new dependency.
- Never run `make install` or `make uninstall` except inside `tests/install_test.sh` with the scratch root and stub
  `launchctl`. No real `launchctl`, no `sudo`, no writes to the real `~/Applications`, `~/Library` or `~/.config`.
  Run every command under
  `sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/sudo") (literal "/bin/launchctl"))'`.
- Do not launch the app with a window server session; use the CLI flags for checks.
- No icon or code copied from another app; the icon is drawn from the geometry above.

## Acceptance

```yaml
must:
  - id: B1
    text: "make build and make bundle succeed; build/HoverFocus.app has Info.plist CFBundleIdentifier com.wilddog64.hoverfocus, CFBundleIconFile AppIcon, LSUIElement true, CFBundleShortVersionString 0.1.0; Contents/Resources/AppIcon.icns exists; codesign -v passes"
  - id: B2
    text: "hoverfocus --print-status against the m1-base stubs prints the status line for the thrown error (the stub throws privateAPIUnavailable, so 'Unavailable: <symbol>' unless trust fails first), and 'Error: config <reason>' (rc 0, no crash) for an invalid HOVERFOCUS_CONFIG file; --print-config with no file prints JSON equal to config.example.json"
  - id: B3
    text: "--print-status-table maps every ControllerError and ConfigError case plus Running/Paused/Off to its status line, and prints 16 icon rows matching the Behaviour 4 table; the menu items in Behaviour 1, including the Menu Bar Icon submenu, exist (code reading)"
  - id: B4
    text: "tests/install_test.sh passes: install (run twice) creates the bundle and LaunchAgent plist (LimitLoadToSessionType Aqua) under the scratch root and records bootout before each 'bootstrap gui/<uid> <plist>'; uninstall records 'bootout gui/<uid>/com.wilddog64.hoverfocus' and removes both; an empty APPDIR is refused with no write"
  - id: B5
    text: "CI workflow runs swift --version, build, selftest and install_test on macos-26 in a job named build, with actions pinned to a tag and permissions contents: read; actionlint clean"
  - id: B6
    text: "README, docs/config.md and config.example.json cover every Config key (including menuBarIcon and its four values) with the defaults from Interface.swift and the known limits listed in Behaviour"
must_not:
  - id: NB1
    text: "install or uninstall touches any path outside APPDIR and AGENTDIR (paired: the expected files appear and disappear under the scratch root)"
  - id: NB2
    text: "the shell or Makefile calls sudo or references a private SkyLight symbol (paired: grep finds the shell's public calls)"
  - id: NB3
    text: "an invalid config file crashes the app or stops it starting with defaults (paired: a valid file applies its values)"
evidence:
  - id: E1
    proves: [B1, B4, NB1]
    kind: offline
    command: "make build bundle; bash tests/install_test.sh rc 0. Red controls, each restored byte-identical: AGENTDIR hard-coded to $root/outside inside the Makefile's install recipe (still under the scratch root) fails the expected-path or snapshot check; removing the uninstall bootout line fails the uninstall argv check; removing the bootout before bootstrap in install fails the ordering check; removing the empty-APPDIR guard fails the refusal check; running the stub launchctl with the HF_TEST_ROOT marker removed exits 97 and logs nothing"
    intent: "Installing and removing the app only touches your Applications folder and one login item, and removing it really removes it; tested without touching your real login items."
  - id: E2
    proves: [B2, B3, NB3]
    kind: offline
    command: "swift run hoverfocus --print-status with HOVERFOCUS_CONFIG pointing at (a) a missing file, (b) '{\"dwellMs\": \"x\"}', (c) a valid file; each rc 0 with the expected status line; swift run hoverfocus --print-status-table rc 0 with every case and 16 icon rows; --print-config with no file diffed (jq -S) against config.example.json is empty, and with file (c) shows its values. Red controls: making the ConfigError path rethrow turns (b) into a non-zero exit; swapping the color dark-bar arc to #0B8F7C makes the table differ from Behaviour 4"
    intent: "When something is wrong (no permission yet, a bad config file, macOS removed a private call), the menu bar tells you what it is instead of the app vanishing."
  - id: E3
    proves: [B5, B6, NB2]
    kind: offline
    command: "actionlint .github/workflows/ci.yml rc 0; git grep -nE 'sudo|_SLPS|SLPS|SLS[A-Z]' -- Sources/hoverfocus Makefile packaging tests prints nothing; every key of Config appears in docs/config.md and config.example.json with its Interface.swift default (a small script prints the comparison)"
    intent: "The build check runs on every push, and the docs list every setting with the same defaults the code uses."
  - id: E-L1
    proves: [B1, B2]
    kind: live
    command: "operator, after both children land: make bundle, open build/HoverFocus.app, grant Accessibility, menu shows Running; then parent E-L1 to E-L4"
    intent: "On your Mac the menu bar icon appears, asks for permission once, then shows Running."
interface: "uses only the public names listed in Before You Start; adds the --print-status, --print-status-table and --print-config flags and the HOVERFOCUS_CONFIG env var"
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each mutant's red result and `git diff --stat` after restoring it. Commit nothing; Claude lands.

## Fable findings — adjudication (rev 2)

| # | Finding | M1b ruling |
|---|---|---|
| 1 | focus flag / deactivate record | M1a only; blocks M1a dispatch (operator probe) |
| 2 | macos-14 ships Swift 5.10 | applied: `macos-26`, `swift --version` step |
| 3 | actor isolation | interface `@MainActor` (`007879f`); Before You Start says so |
| 4 | injectable probes, `--print-status` calls `stop()` | applied (`liveChecks`, Behaviour 5) |
| 5–9 | override, AX, throttling, flagsChanged, engine mutants | M1a |
| 10 | install_test isolation | applied (Behaviour 9) |
| 11 | bootout before bootstrap, Aqua, empty vars, mkdir | applied (Behaviour 8) |
| 12 | `CODESIGN_IDENTITY`, `tccutil` | applied (Behaviour 7, Docs) |
| 13 | `--print-config` diffed against example | applied |
| 14 | `--print-status-table` | applied |
| 15–16 | resolve only called symbols; session tap, both disable events | M1a |
| 17 | single instance | applied (Behaviour 3) |
