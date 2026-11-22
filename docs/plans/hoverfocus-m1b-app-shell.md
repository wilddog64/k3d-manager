# hoverfocus M1b — menu bar app, bundle, install, CI, docs

**Status:** DRAFT rev 1, 2026-11-22 — Fable spec review pending
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release; no `docs/ideas.md` row.
**Parent:** [`hoverfocus-m1-prototype.md`](hoverfocus-m1-prototype.md) (design, facts, interface, file ownership)
**Repo / branch:** `wilddog64/hoverfocus` / task branch from `m1-base` (the interface commit)
**Version:** v0.1.0
**Risk:** low (user-space app and user LaunchAgent; no sudo). The install target writes under `$HOME`; tests run it
only against a scratch HOME with `launchctl` stubbed.
**Implementer:** Flash (shell, packaging, docs). Runs in parallel with M1a (Luna); no shared files. It builds against
the interface stubs, so the app runs but does nothing until M1a lands. **Verifier:** Claude (Sonnet verifier from
`## Acceptance` only).
**Filed:** 2026-11-22
**Intent approved:** pending
**Approval:** operator 2026-11-22 (see parent)

## Before You Start

1. `git log --oneline -1` shows the interface commit on `m1-base`; `swift build` succeeds.
2. Read the parent spec, then `Sources/HoverFocusCore/Interface.swift` and the stub
   `Sources/HoverFocusPlatform/Controller.swift`. Use only the public names the parent lists. Do not edit those files
   or `Package.swift`.

## Behaviour

**App (`Sources/hoverfocus/`):**

1. An `NSApplication` with activation policy `.accessory` (no Dock icon) and an `NSStatusItem` menu:
   - status line (disabled item): `Running`, `Paused`, `Off`, `Needs Accessibility permission` or
     `Unavailable: <symbol>` (from `ControllerError.privateAPIUnavailable`) or `Error: <reason>`;
   - `Enabled` (checkmark; toggles `Config.enabled` in memory and calls `apply`);
   - `Pause for 30 minutes` / `Resume` (sets `isPaused`; a timer clears it);
   - `Grant Accessibility…` (shown only when not trusted; calls `isTrusted(prompt: true)` and retries `start()` every
     2 s for up to 2 minutes);
   - `Reload Config`, `Open Config` (creates the file from `config.example.json`'s content if missing, then opens it
     with the default editor), `Quit`.
2. On launch: load `~/.config/hoverfocus/config.json` (`HOVERFOCUS_CONFIG` env var overrides the path). On
   `ConfigError`, keep defaults, show `Error: config <reason>` and do not crash. Then `start()`; each thrown
   `ControllerError` maps to its status line.
3. The config path, the status text mapping and the menu model live in plain Swift types separate from AppKit
   (`MenuModel.swift`), so a check can run them without a window server: an `--print-status` CLI flag loads config,
   tries `start()`, prints the status line and exits 0 (used by tests and by the operator for a quick check).

**Bundle and install (`Makefile`, `packaging/`):**

4. `make build` → `swift build -c release`; `make selftest` → `swift run hoverfocus-selftest`; `make bundle` →
   `build/HoverFocus.app` with `Contents/MacOS/hoverfocus`, `Contents/Info.plist` (`CFBundleIdentifier`
   `com.wilddog64.hoverfocus`, `LSUIElement` true, `CFBundleShortVersionString` 0.1.0,
   `LSMinimumSystemVersion` 14.0), signed ad hoc (`codesign --force --sign -`).
5. `make install` copies the bundle to `$(APPDIR)` (default `$(HOME)/Applications`) and writes
   `$(AGENTDIR)/com.wilddog64.hoverfocus.plist` (default `$(HOME)/Library/LaunchAgents`) from
   `packaging/com.wilddog64.hoverfocus.plist.tmpl` (`RunAtLoad` true, `KeepAlive` `SuccessfulExit` false,
   `ProgramArguments` the installed binary), then `$(LAUNCHCTL) bootstrap gui/$$(id -u) <plist>`. `make uninstall`
   runs `$(LAUNCHCTL) bootout gui/$$(id -u)/com.wilddog64.hoverfocus` (ignore not-loaded), removes the plist and the
   bundle. `LAUNCHCTL` defaults to `launchctl`. Neither target uses `sudo` or touches any path outside `APPDIR` and
   `AGENTDIR`.
6. `tests/install_test.sh` (`set -euo pipefail`): asserts it runs with a scratch `HOME` under `mktemp -d` first, puts a
   stub `launchctl` that records argv on `PATH` and as `LAUNCHCTL`, runs `make install` then `make uninstall`, and
   checks the files appear and disappear, the recorded `bootstrap`/`bootout` argv, and that nothing else under the
   scratch HOME changed. It also builds the bundle and checks the Info.plist keys with `plutil -extract`.

**CI (`.github/workflows/ci.yml`):** on push and pull_request: `macos-14` runner, `actions/checkout@v4`,
`permissions: contents: read`, steps `swift build`, `swift run hoverfocus-selftest`, `bash tests/install_test.sh`.

**Docs:** `README.md` (what it does, build, install, granting Accessibility, the menu, logs with
`log stream --predicate 'subsystem == "com.wilddog64.hoverfocus"'`, known limits: private API that can break on a
macOS update, ad-hoc signing makes macOS ask for Accessibility again after each rebuild, Electron and full-screen
apps may behave differently, personal machines only), `docs/config.md` (every `Config` key, type, default, range),
`config.example.json` (every key with its default), `LICENSE` (MIT unless the operator says otherwise), `.gitignore`
(`.build/`, `build/`).

## Files

| File | Change |
|---|---|
| `Sources/hoverfocus/main.swift` | replace stub |
| `Sources/hoverfocus/*.swift` | new (app delegate, menu, `MenuModel.swift`) |
| `Makefile` | new |
| `packaging/Info.plist`, `packaging/com.wilddog64.hoverfocus.plist.tmpl` | new |
| `tests/install_test.sh` | new |
| `.github/workflows/ci.yml` | new |
| `README.md`, `docs/config.md`, `config.example.json`, `LICENSE`, `.gitignore` | new |

## Contract readers

- `Interface.swift` public names (reader: this spec; writer: Claude's interface commit; M1a keeps them).
- `~/.config/hoverfocus/config.json` and `HOVERFOCUS_CONFIG`: writer the operator; readers `ConfigLoader` (M1a) via
  this shell. `config.example.json` and `docs/config.md` must match `Config`'s defaults in `Interface.swift`.
- LaunchAgent label `com.wilddog64.hoverfocus`, `~/Applications/HoverFocus.app`: writer `make install`; readers
  `make uninstall`, README.
- os_log subsystem `com.wilddog64.hoverfocus` (writer M1a): reader README.

## What NOT to Do

- No edit to `Package.swift`, `Interface.swift`, or any file M1a owns. No new dependency.
- Never run `make install` or `make uninstall` except inside `tests/install_test.sh` with the scratch HOME and stub
  `launchctl`. No real `launchctl`, no `sudo`, no writes to the real `~/Applications`, `~/Library` or
  `~/.config`.
- Do not launch the app with a window server session; use `--print-status` for checks.

## Acceptance

```yaml
must:
  - id: B1
    text: "make build and make bundle succeed; build/HoverFocus.app has Info.plist CFBundleIdentifier com.wilddog64.hoverfocus, LSUIElement true, CFBundleShortVersionString 0.1.0, and codesign -v passes"
  - id: B2
    text: "hoverfocus --print-status against the m1-base stubs prints 'Needs Accessibility permission' or 'Unavailable: <symbol>' per the thrown error, and 'Error: config <reason>' (rc 0, no crash) for an invalid HOVERFOCUS_CONFIG file"
  - id: B3
    text: "MenuModel maps every ControllerError and ConfigError case to its status line, and the menu items listed in Behaviour 1 exist (checked by code reading plus --print-status cases)"
  - id: B4
    text: "tests/install_test.sh passes: install creates the bundle and LaunchAgent plist under the scratch HOME and records 'bootstrap gui/<uid> <plist>'; uninstall records 'bootout gui/<uid>/com.wilddog64.hoverfocus' and removes both"
  - id: B5
    text: "CI workflow runs build, selftest and install_test on macos-14 with actions pinned to a tag and permissions contents: read; actionlint clean"
  - id: B6
    text: "README, docs/config.md and config.example.json cover every Config key with the defaults from Interface.swift and the known limits listed in Behaviour"
must_not:
  - id: NB1
    text: "install or uninstall touches any path outside APPDIR and AGENTDIR (paired: the expected files appear and disappear under the scratch HOME)"
  - id: NB2
    text: "the shell or Makefile calls sudo or references a private SkyLight symbol (paired: grep finds the shell's public calls)"
  - id: NB3
    text: "an invalid config file crashes the app or stops it starting with defaults (paired: a valid file applies its values)"
evidence:
  - id: E1
    proves: [B1, B4, NB1]
    kind: offline
    command: "make build bundle; bash tests/install_test.sh rc 0. Red controls, each restored byte-identical: AGENTDIR hard-coded to /tmp/hf-agent-mutant in the Makefile makes the test fail on the 'nothing else changed / expected path' check; removing the bootout line makes the uninstall argv check fail; install_test.sh exits non-zero before running make if HOME is not under the mktemp dir (shown by running it with HOME unset to the scratch)"
    intent: "Installing and removing the app only touches your Applications folder and one login item, and removing it really removes it; tested without touching your real login items."
  - id: E2
    proves: [B2, B3, NB3]
    kind: offline
    command: "swift run hoverfocus --print-status with HOVERFOCUS_CONFIG pointing at (a) a missing file, (b) '{\"dwellMs\": \"x\"}', (c) a valid file; each rc 0 with the expected status line; red control: making the ConfigError path rethrow turns (b) into a non-zero exit"
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
interface: "uses only the public names listed in the parent; adds the --print-status flag and the HOVERFOCUS_CONFIG env var"
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each mutant's red result and `git diff --stat` after restoring it.
