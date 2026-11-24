# hoverfocus v0.0.2 F1 — install: wait for unload, detect a non-GUI session, safe paths, re-grant hint

**Status:** spec rev 3 — Fable reviewed rev 1 (NEEDS FIXES: 1 blocker, 6 should-fix, 4 nits; all applied) and rev 2
(2026-11-24, NEEDS FIXES: 1 blocker (SwiftPM nested sandbox), 4 should-fix, 3 nits; all applied); GUI `managername`
gate closed; not dispatched
**Tracked:** hoverfocus (OOB repo), not a k3d-manager release.
**Parent:** [`hoverfocus-v0.0.2-bug-batches.md`](hoverfocus-v0.0.2-bug-batches.md) (batch F1)
**Repo / branch:** `wilddog64/hoverfocus`, task branch from `v0.0.2` (cut from `main` at `d426f18`, tag `v0.0.1`)
**Risk:** low (user LaunchAgent install; never `sudo`, only prints a `sudo` command). Tests run install only against a
scratch root with `launchctl` stubbed.
**Implementer:** Flash (`agy`; Makefile, shell, docs). Runs in parallel with L1 (no shared file). **Verifier:** Claude,
from `## Acceptance` only.
**Filed:** 2026-11-23
**Intent approved:** operator, 2026-11-24
**Approval:** operator 2026-11-23 ("plan for bugs distributions between flash and luna"; "ship v0.0.1 and fix bugs in
v0.0.2")

## Fixes

| Input | Defect (v0.0.1) |
|---|---|
| B3 part 1 | `make install` runs `bootout` then `bootstrap` at once; reinstalling while the old agent is loaded raced the unload and `bootstrap` returned error 37 |
| B3 part 2 | over SSH (`launchctl managername` = `Background`) bootstrapping the `LimitLoadToSessionType Aqua` plist into `gui/<uid>` fails (`Bootstrap failed: 5: Input/output error`); install gives no hint. Workaround: `sudo launchctl asuser <uid> launchctl bootstrap gui/<uid> <plist>` |
| B3 part 4 (doc half) | ad-hoc signing makes the Accessibility grant build-specific; install does not say how to re-grant. (A stable signing identity waits on an operator decision; not in this batch.) |
| Argon #3 | `Makefile:37` `sed 's|__PROGRAM__|$(APPDIR)/...|g'` breaks when the path contains `|` or `&`, and the value is not XML-escaped |

## External behaviour (proof)

Captured read-only by Claude on m4-air, macOS 26.5.2, over SSH, 2026-11-23:

- `launchctl print gui/<uid>/<label>` → rc **113** when the service is not loaded, rc **0** when loaded
  (`com.apple.Finder`).
- `launchctl managername` over SSH → `Background`, rc 0 (matches the m2 report in the B3 doc).
- GUI Terminal session: `launchctl managername` → `Aqua` (operator on m2, macOS 26, 2026-11-24, while debugging the
  B3 error 5: "it show aqua"). Dispatch gate (Fable 15) closed.
- Whether `bootout` returns before the job is fully gone is not proven; the wait below is defensive and costs one
  `print` call when `bootout` is synchronous.

## Before You Start

1. `git log --oneline -1` shows `d426f18`. On `d426f18`, `bash tests/install_test.sh` under the sandbox profile fails at
   `make bundle` → `swift build -c release` (`sandbox_apply: Operation not permitted`: SwiftPM's own sandbox cannot
   nest inside `sandbox-exec`; Fable 2026-11-24). Behaviour 8 adds `SWIFT_BUILD_FLAGS`; every test command in this spec
   runs as `SWIFT_BUILD_FLAGS=--disable-sandbox bash tests/install_test.sh` under the profile. Never run it without the
   profile; the baseline is CI green on `d426f18` (v0.0.1 PR #1), so start with Behaviour 8 and then run the test.
2. Read `Makefile`, `tests/install_test.sh`, `packaging/com.wilddog64.hoverfocus.plist.tmpl`, `README.md`.
3. Do not edit any file outside `## Files`.

## Behaviour

1. **Paths are never re-parsed (Argon #3).** `export APPDIR AGENTDIR LAUNCHCTL CODESIGN_IDENTITY` in the Makefile and
   refer to them in recipes as shell variables (`"$$APPDIR"`), not `$(APPDIR)` text. The LaunchAgent plist is written
   by copying the template, then
   `plutil -replace ProgramArguments -array <plist>` followed by
   `plutil -insert ProgramArguments.0 -string "$$APPDIR/HoverFocus.app/Contents/MacOS/hoverfocus" <plist>` (plutil
   does the XML escaping). **Not** `plutil -replace ProgramArguments.0`: on an array index it inserts and leaves
   `__PROGRAM__` as a second argument (Fable 9, reproduced by Claude on macOS 26.5.2). Not PlistBuddy `Set` (drops
   `'`). `sed` is no longer used for it; keep the placeholder in the template so the file stays a valid plist. The
   empty-variable guards use the shell variables too.
   Session check, `bootout`, poll and `bootstrap` (Behaviour 2-3) share state, so they are **one `\`-joined shell
   block** in the recipe (each make recipe line is its own shell), with `"$$LAUNCHCTL"` quoted.
2. **Session check (B3 part 2).** Before any `bootout`/`bootstrap`, install reads `"$$LAUNCHCTL" managername`. A
   failing command or empty output counts as non-`Aqua`. If it is not exactly `Aqua`, install still copies the bundle and writes the plist, then skips `bootout`/`bootstrap`, prints
   to stderr:

   ```
   hoverfocus: not a GUI login session (launchctl managername: <value>); files are installed but the agent is not loaded.
   To load it from this session, run:
     sudo launchctl asuser <uid> launchctl bootout gui/<uid>/com.wilddog64.hoverfocus
     sudo launchctl asuser <uid> launchctl bootstrap gui/<uid> '<absolute plist path>'
   ```

   (the plist path single-quoted, since `AGENTDIR` may contain spaces)

   (the first line may fail harmlessly when nothing is loaded) and exits 0. Uninstall does the same check: in a
   non-`Aqua` session it removes the files, skips `bootout` and prints the `asuser … bootout` line to stderr. Neither target runs
   `sudo`.
3. **Wait for unload (B3 part 1).** In an `Aqua` session, after `bootout` (failure ignored), poll
   `$$LAUNCHCTL print gui/<uid>/com.wilddog64.hoverfocus` until it exits non-zero, sleeping 0.1 s between tries, at
   most `BOOTOUT_WAIT_TRIES` tries (`BOOTOUT_WAIT_TRIES ?= 50`, exported, i.e. 5 s). Then `bootstrap`. If it is still
   loaded after the last try, print `hoverfocus: agent still loaded after bootout; not bootstrapping` to stderr and exit
   non-zero without calling `bootstrap`. Uninstall runs `bootout` only (no wait needed).
4. **Re-grant hint (B3 part 4).** After the files are installed, on both the `Aqua` and the non-`Aqua` path (the SSH
   case needs it most), when `"$$CODESIGN_IDENTITY"` is `-` (ad hoc), print to stdout:

   ```
   hoverfocus: ad-hoc signed build. If the menu shows "Needs Accessibility permission" although HoverFocus is enabled
   in System Settings, reset the old grant and grant again:
     tccutil reset Accessibility com.wilddog64.hoverfocus
   then enable HoverFocus in System Settings > Privacy & Security > Accessibility.
   ```

   Not printed for a named identity. (L1 makes the app notice the grant on its own; no kickstart needed.)
5. **`tests/install_test.sh`.** Keep every v0.0.1 check (scratch root, marker, snapshot, refusal, Info.plist, codesign)
   and extend the stub `launchctl`:
   - `managername` prints the contents of `$root/managername` (default file content `Aqua`), rc 0;
   - `print …` exits 0 while the integer in `$root/print_loaded` is > 0 (decrementing it each call), else 113;
   - every call is still appended to `$root/launchctl.log`, and the stub still exits 97 without the marker;
   - the stub carries a comment naming its source capture: `m4-air, macOS 26.5.2, 2026-11-23: print of a missing
     service rc 113; managername over SSH prints Background`.
   Add a stub `sudo` in `$root/bin` (first on `PATH`) that appends to `$root/sudo.log` and exits 97; every case asserts
   `sudo.log` is absent or empty (Fable 12: hosted runners have passwordless sudo, and the sandbox profile is local
   only). Replace the fixed-line-number log checks with order checks over the bootout/print/bootstrap lines that
   ignore `managername` lines. Each case writes `$root/managername` and `$root/print_loaded` **before** taking its
   snapshot, and the snapshot comparison excludes `launchctl.log` and `sudo.log` (today it excludes only
   `launchctl.log`, `install_test.sh:38`). New cases, each with its own scratch state reset:
   - **wait:** `print_loaded=3` → log has `bootout …`, then 4 `print` calls, then `bootstrap gui/<uid> <plist>`;
   - **timeout:** `print_loaded=1000`, `BOOTOUT_WAIT_TRIES=3` → install exits non-zero, stderr has `still loaded`,
     no `bootstrap` in the log;
   - **SSH session:** `managername=Background` → install rc 0, bundle and plist exist, no `bootout`/`bootstrap` in the
     log, stderr has `sudo launchctl asuser <uid> launchctl bootstrap gui/<uid> '<plist>'` with the real plist path,
     single-quoted as Behaviour 2 prints it;
     uninstall in the same state removes both files, logs no `bootout`, prints the `asuser … bootout` line;
   - **odd path:** `APPDIR="$root/home/Apps & Co|x <y> 'z'"`, created **before** the case's snapshot (install
     `mkdir -p`s it and uninstall leaves the directory, as in v0.0.1) → install rc 0; `plutil -lint` passes on the
     installed plist; `plutil -extract ProgramArguments raw` is `1` (one element); `plutil -extract
     ProgramArguments.0 raw` equals `$APPDIR/HoverFocus.app/Contents/MacOS/hoverfocus` exactly; `grep -c __PROGRAM__`
     on the installed plist is 0; the bundle exists at that path; uninstall removes it and the snapshot check holds.
     The default-path case asserts the same count and no `__PROGRAM__`;
   - **hint:** run with `CODESIGN_IDENTITY=-` passed explicitly (`Makefile:4` is `?=` and yields to the environment);
     the install output has `tccutil reset Accessibility com.wilddog64.hoverfocus`. The
     named-identity branch is not run (CI has no signing identity and `bundle` would fail); it is checked by code
     reading.
6. **README.** Installation: the SSH case and the printed `asuser` commands; re-installing is safe (waits for the old
   agent). Granting Accessibility: grant in System Settings or via the menu; HoverFocus notices within a few seconds
   (L1); after a rebuild of an ad-hoc build run the `tccutil reset` line. Known limitations: keep the ad-hoc line, and
   add: `Some apps can raise their own window when they receive focus (seen with Safari on macOS 26). Add such apps to
   ignoreApps (bundle IDs), for example "ignoreApps": ["com.apple.Safari"].` The Tested-apps table from the parent
   plan's P1 matrix is **deferred** to a docs batch after P1 runs (no data yet).
7. **`docs/config.md:6`** (L1 contract reader): replace "keeps the defaults, reports the error … and continues
   running" with: on an invalid file HoverFocus shows `Error: config <reason>` and stops focusing until a valid file
   is loaded with Reload Config.

8. **`SWIFT_BUILD_FLAGS`.** `SWIFT_BUILD_FLAGS ?=` (empty default) and the `build` recipe becomes
   `swift build -c release $(SWIFT_BUILD_FLAGS)`. CI and normal installs are unchanged; the sandboxed test run sets
   `--disable-sandbox`.

**Land order:** L1 and F1 both land on `v0.0.2` before the release PR to `main`; the README and `docs/config.md` text
describe L1's behaviour, so `v0.0.2` is not merged with F1 alone. Test runtime: each `make install` re-runs `bundle`
(icon render + codesign), about seven runs; acceptable.

## Files

| File | Change |
|---|---|
| `Makefile` | Behaviour 1-4, 8 |
| `tests/install_test.sh` | Behaviour 5 |
| `README.md` | Behaviour 6 |
| `docs/config.md` | Behaviour 7 (one sentence) |

## Contract readers

- `LAUNCHCTL`, `APPDIR`, `AGENTDIR` (writer: Makefile defaults, operator overrides): readers `tests/install_test.sh`,
  `.github/workflows/ci.yml` (runs the test, no overrides), README. Now exported to the recipe environment.
- New `BOOTOUT_WAIT_TRIES` (writer: Makefile default 50): reader `tests/install_test.sh` (timeout case).
- New `SWIFT_BUILD_FLAGS` (writer: Makefile default empty; the operator or worker environment): reader the `build`
  recipe only. `.github/workflows/ci.yml` does not set it.
- LaunchAgent label `com.wilddog64.hoverfocus` and plist path: unchanged; readers `make uninstall`, README, the printed
  `asuser` commands.
- `packaging/com.wilddog64.hoverfocus.plist.tmpl` `__PROGRAM__`: was read by `sed` in `Makefile:37`; after this change
  no reader replaces it textually (plutil sets the value).

## What NOT to Do

- Never run `make install`/`uninstall` outside `tests/install_test.sh`'s scratch root with the stub `launchctl`. No real
  `launchctl`, no `sudo`, no writes to the real `~/Applications`, `~/Library` or `~/.config`. Run every command under
  `sandbox-exec -p '(version 1)(allow default)(deny process-exec (literal "/usr/bin/sudo") (literal "/bin/launchctl"))'`.
- No `tccutil` call anywhere (print only). No code signing identity creation.
- No edit outside `## Files`; no Swift change (L1 owns the app).

## Acceptance

```yaml
must:
  - id: F1-M1
    text: "in an Aqua session install runs bootout, polls launchctl print until it exits non-zero (at most BOOTOUT_WAIT_TRIES tries, 0.1 s apart), then bootstrap; if still loaded after the last try it exits non-zero without bootstrap"
  - id: F1-M2
    text: "when launchctl managername is not Aqua, install writes the bundle and plist, skips bootout/bootstrap, prints the sudo launchctl asuser bootout and bootstrap commands with the real uid and plist path, and exits 0; uninstall removes the files and prints the asuser bootout line"
  - id: F1-M3
    text: "an APPDIR containing space, &, |, <, > and ' installs a plist that passes plutil -lint with ProgramArguments.0 equal to the installed binary path, and uninstall removes it"
  - id: F1-M4
    text: "an ad-hoc install prints the tccutil reset Accessibility com.wilddog64.hoverfocus hint; README documents the SSH case, safe reinstall and re-grant"
must_not:
  - id: F1-N1
    text: "install calls bootstrap while the stub still reports the agent loaded (paired: with print_loaded=0 bootstrap follows bootout directly after one print)"
  - id: F1-N2
    text: "install calls bootstrap or bootout in a non-Aqua session, or runs sudo (paired: with managername=Aqua both are logged)"
  - id: F1-N3
    text: "a path with | or & corrupts the plist or the program path (paired: the default path still installs and extracts equal)"
  - id: F1-N4
    text: "regression guard (already green on v0.0.1): install or uninstall touches any path outside APPDIR and AGENTDIR (paired: the expected files appear and disappear under the scratch root)"
  - id: F1-N5
    text: "regression guard (already green on v0.0.1, whose sed leaves one element): the installed plist keeps __PROGRAM__ or has more than one ProgramArguments entry (paired: ProgramArguments.0 equals the installed binary path)"
evidence:
  - id: F1-E1
    proves: [F1-M1, F1-N1, F1-N4]
    kind: offline
    command: "SWIFT_BUILD_FLAGS=--disable-sandbox bash tests/install_test.sh rc 0 under the sandbox profile, showing the wait, timeout and v0.0.1 snapshot checks. Red controls, each restored byte-identical: remove the print poll loop (v0.0.1 behaviour) — the wait case fails; make the loop ignore BOOTOUT_WAIT_TRIES exhaustion and bootstrap anyway — the timeout case fails; hard-code the plist destination to $$HOME/outside in the install recipe — the snapshot or expected-path check fails"
    intent: "make install while the app is running waits for the old copy to stop before starting the new one, so error 5 no longer happens."
  - id: F1-E2
    proves: [F1-M2, F1-N2]
    kind: offline
    command: "same run: SSH-session case passes. Red controls: remove the managername check (v0.0.1 behaviour) — the SSH case fails because bootout/bootstrap are logged; change the printed bootstrap line to drop asuser — the stderr check fails; add a `-sudo true` line to the install recipe (the `-` keeps make going past the stub's exit 97, so the test reaches the sudo.log assertion instead of stopping under `set -e`) — the sudo.log check fails. grep -nw sudo Makefile shows sudo only inside echo/printf strings (not git grep -E '\\b', which matched nothing on macOS; Fable 11)"
    intent: "make install over SSH or in an SSH-started tmux copies the app and prints the exact commands to run instead of failing."
  - id: F1-E3
    proves: [F1-M3, F1-N3, F1-N5]
    kind: offline
    command: "same run: odd-path case passes. Red controls: restore the v0.0.1 sed line for the plist — the odd-path case fails (sed 'bad flag' or the extract check), while the default-path checks still pass; use plutil -replace ProgramArguments.0 instead of replace-array + insert — the element-count and __PROGRAM__ checks fail"
    intent: "Installing to a folder whose name has spaces or symbols such as & or | still produces a working startup file."
  - id: F1-E4
    proves: [F1-M4]
    kind: offline
    command: "same run: hint case passes; red control: delete the hint echo — the hint check fails. README sections quoted with line numbers"
    intent: "Install reminds you how to re-grant Accessibility after a reinstall, and the README explains the SSH case."
  - id: F1-EL
    proves: [F1-M1, F1-M2]
    kind: live
    command: "operator on m2 (home): in a GUI Terminal, launchctl managername prints Aqua; make install twice in a row succeeds with no error 37 and the menu bar icon is back; over SSH from m4, make install prints the asuser commands and running them loads the agent"
    intent: "On m2, make install twice in a row from a GUI Terminal shows no error and the menu bar icon returns; over SSH from m4 it prints the commands and starts nothing."
interface: "adds BOOTOUT_WAIT_TRIES; exports APPDIR, AGENTDIR, LAUNCHCTL to recipes; install output gains the session and re-grant messages"
```

## Worker definition of done

- Change only the files in the table. Report each command, its rc and the proving lines; list every error seen; show
  each red control's failing output and `git diff --stat` after restoring it. Commit nothing; Claude lands.

## Live check log

- 2026-11-24 17:57, m2 (macOS 26.5.1), GUI Terminal, `make install` of `42273f0`: no error; old agent (pid since 17:34)
  gone, new pid started at the install second; plist `ProgramArguments` = one app-path entry. **F1-EL first install: pass.**
  Pending: a second `make install` straight after (no error 37, icon back); over SSH from m4, prints the asuser commands
  and starts nothing.
- 2026-11-24 ~04:03 PST, m2, GUI iTerm, `make install` of `42273f0` twice in a row: both runs complete, no error 37, no
  "still loaded after bootout"; launchd `state = running`, `last exit code = (never exited)`, process started 04:03:36
  from the new bundle (Claude, read-only over SSH). **F1-EL GUI half: pass (second run).** Pending: over SSH from m4.
