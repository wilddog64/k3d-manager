# HoverFocus v0.0.3 — plan

**Filed:** 2026-11-24
**Status:** plan — D1-D3 decided (operator, 2026-11-24); P3 PASS (2026-11-25); P2 rc 1002 re-diagnosed (no AppKit connection); P2 DONE: variant Y passes all 8 apps (P2b + P2c); child specs L3/F2/U1 rev 1 written 2026-11-25, blind reviews running (L3 Fable + Neon; F2, U1 Argon + Neon)
**Repo:** `hoverfocus`, branch `v0.0.3` cut from `main` after v0.0.2 merges
**Approval:** "let's plan to work on hoverfocus v0.0.3" (operator, 2026-11-24); Electron + indicator → v0.0.3 and local
signing identity approved the same day

Theme: **focus works in every common app, and the user can see it.** v0.0.2 ships L1 (reload fails closed, trust
watch) and F1 (install); it is waiting on the L1 `Running` confirmation, the F1 `sudo launchctl asuser` step and its
PR review.

## Inputs

| Item | Doc | Priority |
|---|---|---|
| Electron apps (Slack, VS Code) get no focus | `docs/hoverfocus/bugs/2026-11-24-hoverfocus-electron-apps-no-focus.md` | P2 |
| No visual cue on the hover-focused window | `docs/hoverfocus/bugs/2026-11-24-hoverfocus-no-visual-focus-indicator.md` | P2 |
| Same-app window switch has no effect (B1) | `docs/hoverfocus/bugs/2026-11-23-hoverfocus-same-app-window-switch-no-effect.md` | P2 (proposed) |
| Terminal hollow cursor / menu shortcuts need a click (B2) | `docs/hoverfocus/bugs/2026-11-23-hoverfocus-iterm-hollow-cursor-after-no-raise-focus.md` | P3 → P2 proposed |
| Safari: Cmd+W does not close the tab | `docs/hoverfocus/bugs/2026-11-23-hoverfocus-safari-no-focus.md` (P1 matrix) | P2 (proposed) |
| AX element cache never evicts closed windows (A2) | `docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md` #2 | — |
| Stable signing so the Accessibility grant survives rebuilds (B3 part 4) | `docs/hoverfocus/bugs/2026-11-23-hoverfocus-install-launchagent-and-tcc-grant-gaps.md` | decided 2026-11-24 |
| Errors are a grey line: show red + one notification | `docs/ideas.md` row 2026-11-24 | idea |

## Batches

| Batch | Worker | Scope | Files | Blocked on |
|---|---|---|---|---|
| **P2** | Claude + operator (live, m2) | Finish the P1 matrix (Chrome, Mail, Terminal.app); Electron: does the AX lookup find the `AXWindow` at all, before and after setting `AXManualAccessibility`; Safari Cmd+W key-window gap; same-app candidates (`kAXMainAttribute` on the window without activating) | scratch probe only | operator at m2 |
| **P3** | Claude + operator (live, m2) | Signing proof: a self-signed code-signing identity in the login Keychain; rebuild twice; the Accessibility grant survives (designated requirement stays the same) | scratch only | operator at m2 (Keychain prompt) |
| **L3** | Luna | Focus correctness from P2's winning variant: B1, B2, Electron, Safari Cmd+W, A2 eviction; selftest rows per app class | `Sources/HoverFocusPlatform/Controller.swift`, `Sources/CSkyLight/*`, selftest | P2 |
| **F2** | Flash | `make signing-identity` (operator-run, creates the identity) and `CODESIGN_IDENTITY` defaulting to it when present, else ad-hoc + the reset hint; README install section and a "Tested apps" table from P1/P2 | `Makefile`, `tests/install_test.sh`, `README.md` | P3 |
| **U1** | Luna | Visible errors: status line in red (attributed title); one Notification Center message on each transition into an error (config invalid, event tap, Accessibility lost), none while it persists | `Sources/hoverfocus/AppDelegate.swift`, `Sources/HoverFocusCore/Health.swift` (new), `Sources/HoverFocusCore/AppCoordinator.swift`, selftest (`MenuModel.swift` read-only, per the child spec) | P3 (notification permission needs the stable identity) |
| **U2** | Luna | Focus indicator per D2 | new `Sources/hoverfocus/FocusIndicator.swift`, one hook in `Controller.swift` | L3 (shares `Controller.swift`) |

Order: P2 and P3 together (one m2 session) → L3 and F2 in parallel → U1 after L3 lands (both edit
`Sources/hoverfocus-selftest/main.swift`; one dispatch per file, found while writing the child specs 2026-11-25) → U2
after L3 lands. Child specs: [`L3`](hoverfocus-v0.0.3-l3-focus-correctness.md),
[`F2`](hoverfocus-v0.0.3-f2-signing-identity.md), [`U1`](hoverfocus-v0.0.3-u1-visible-errors.md). U1 adds
`Sources/HoverFocusCore/AppCoordinator.swift` (Accessibility-loss detection) and L3 adds `RecentCache.swift`; the
README's Known Limitations and Menu Bar paragraphs are Claude's edits at release, after the live checks.
Five dispatches plus two probes. A fix that depends on macOS behaviour carries the probe result before dispatch.

## Probe results

### P3 — local signing identity keeps the Accessibility grant (PASS, m2-air, macOS 26.5.1, 2026-11-25)

Kit: `hf-p3-signing.sh` (scratch, copied to m2 `~/hf-probe/`), checkout `42273f0`; logs `~/hf-p3-20261125T042212.txt`
(run 1, inconclusive) and `~/hf-p3-20261125T042939.txt` (run 2). TCC rows read by Claude over SSH (read-only `sqlite3` on
`/Library/Application Support/com.apple.TCC/TCC.db`).

- Identity: self-signed "HoverFocus Local Signing" (RSA 2048, EKU codeSigning, `/usr/bin/openssl` LibreSSL 3.3.6), imported
  into the login Keychain with `-T /usr/bin/codesign`; `security find-identity -p codesigning` lists it as
  `CSSMERR_TP_NOT_TRUSTED`, and codesign signs with it anyway (no trust setting needed).
- Designated requirement: `identifier "com.wilddog64.hoverfocus" and certificate leaf = H"70e9d86b…"` on all three builds
  (cdhashes `50c5fcc5…`, `bfbf8e68…`, `09dcd621…`; builds 2-3 = real `make install` plus an Info.plist stamp and re-sign so
  each binary differs). Ad-hoc control: `cdhash H"63fc6082…"` (changes every build — the old behaviour).
- TCC: one grant (remove + re-add in a freshly opened System Settings) gave `auth_value 2`, csreq 80 B at 04:31:33; the row
  was unchanged after builds 2 and 3.
- Running build 3 (pid 67085): passed `Controller.start`'s `isTrusted()` guard and owns an enabled session event tap (mask
  `e0000fe`, `CGGetEventTapList` over SSH); operator hover recheck: typing went to a TextEdit window behind iTerm.
  (The script's build-3 "fail" was a y/n answer given ~5 s after restart; the objective checks and the recheck pass.)
- Run 1 lesson: after `tccutil reset`, an already-open System Settings shows a stale ON switch; the TCC row stayed
  `auth_value 0, auth_reason 4` with no csreq. F2's README must say: quit System Settings, remove, re-add.

### P2 — make-key records: the rc 1002 re-diagnosed (desk check, Claude, 2026-11-25)

The P2 run of 2026-11-25 (13 usable rounds; the probe's own frontmost/pointer guards skipped the rest) showed B
activates the app without making the hovered window *key* in Chrome, Mail, VS Code, Safari and same-app TextEdit,
and BM/BF do not fix it. So L3 needs the "make key window" event records that M1a variants C/D tried and dropped.

- **Layout is not the cause.** The probe's record (`probe/focus-flags:probe/focus_probe.swift:63-67`, 0xf8 bytes,
  0x04=0xf8, 0x3a=0x10, 0x20..0x2f=0xff, wid at 0x3c, then 0x08=0x01 and 0x08=0x02) matches byte for byte
  `koekeishiya/yabai` tag `v7.1.25` `src/window_manager.c:1269-1291` (`window_manager_make_key_window`) and
  `sbmpost/AutoRaise` tag `v5.7` `AutoRaise.mm:173-186` (focus-follows-mouse without raise, the same product idea).
- **rc 1002 is `kCGErrorInvalidConnection`** (`CGError.h`, macOS SDK 26.5): the calling process had no window-server
  connection. The probe was a bare `swift focus_probe.swift` script that never initialised AppKit. yabai calls
  `NSApplicationLoad()` and then `SLSMainConnectionID()` before any record (`src/yabai.c:139-143` at `v7.1.25`).
- **The shipped app already has the connection** (`Sources/hoverfocus/main.swift:70` `NSApplication.shared`), so the
  1002 was most likely a probe artifact, not a platform refusal.
- **Variant D was also wrong:** yabai's deactivate/activate records set `0x08=0x0d` with `0x8a=0x02`/`0x01` and a 40 ms
  gap (`window_manager.c:1300-1318`); the probe set only `0x8a`.

Next probe (P2b, Claude writes, one short operator run on m2): an AppKit-initialised probe (`NSApplication.shared`
plus `SLSMainConnectionID()` before posting) that runs B + make-key (and yabai-exact D) per app, restores the probe
terminal to the front itself between variants, and checks typed-text delivery itself via AX `AXValue` on the target's
focused text element; the operator answers only "did it come to the front?". Pass for L3 = record rc 0 and text lands
with no raise in TextEdit (two windows), Chrome, Safari and Mail.

P2b kit written 2026-11-25 and on m2 at `~/hf-probe/hf-p2b.sh` + `hf-p2b-probe.swift` (type-checks with Swift 6.3.3
on m2). Variants B, BK (B + make-key) and Y (yabai v7.1.25 `focus_window_without_raise` exactly: same-app
deactivate/activate records, `kCPSUserGenerated`, make-key), two repeats each. It stops with "probe defect" if
`SLSMainConnectionID()` is 0 or a self make-key on its own terminal window is refused, so a repeat of rc 1002 cannot
pass as a result. Typing is checked by a synthetic token read back through `AXFocusedUIElement`/`AXValue` (operator
asked only when an app's text is unreadable); raise is measured by window order. Log: `~/hf-p2b-<timestamp>.txt`.

### P2b — results (m2-air, macOS 26.5.1, 2026-11-25 16:16 PST, log m2 `~/hf-p2b-20261125T161602.txt`)

Connection self-check passed (`SLSMainConnectionID` 5373435, self make-key rc [0,0]); all 54 trials' records rc 0, so
the M1a rc 1002 was the probe, not the platform. Two repeats per variant; raise from window order.

| App | B (v0.0.2) | BK (B + make-key) | Y (yabai exact) |
|---|---|---|---|
| TextEdit | pass | pass | pass |
| TextEdit, two windows (same app) | pass (contradicts live B1, see below) | pass | pass |
| Safari probe page | lands (operator saw), text unreadable | **pass** (read back) | **pass** |
| Slack (Electron) | lands but **raised** both times | **pass** | **pass** |
| Terminal.app | pass | pass | pass |
| Chrome probe page | read-back no | read-back no | read-back no |
| Mail new message | 1 of 4 seen | read-back no | read-back no |
| VS Code (Electron) | not seen | read-back no | read-back no |

- BK/Y fix the Slack raise and Safari key status with no raise anywhere. BK and Y are equal here; prefer **Y** (upstream
  sequence, explicit same-app branch).
- Chrome/Mail/VS Code are **inconclusive**: "read-back no" means the token was not in the app's AX focused element, which
  can be a different element (Chrome refused AX enablement: `AXManualAccessibility` rc -25205, `AXEnhancedUserInterface`
  rc -25208), and the probe erased the token, so nobody looked. Follow-up P2c: `HF_P2B_ASK_ALL=1 ~/hf-probe/hf-p2b.sh`
  for scenarios 3, 5, 6 (no read-back, no erase, operator reports the tokens seen).
- Same-app B passed in the probe but failed live (E-L1 step 3). Candidate cause for L3: `Sources/HoverFocusCore/Engine.swift:59`
  skips when `target.windowID == state.focusedWindowID`, and AX focused-window state was shown in P2 to report the target
  while keys went elsewhere. L3 must prove which (selftest row plus live recheck).

### P2c — Chrome, Mail, VS Code by operator sight (m2-air, 2026-11-25 16:31 PST, log m2 `~/hf-p2b-20261125T163145.txt`)

`HF_P2B_ASK_ALL=1`: no read-back, no erase; the operator listed the tokens visible in each app. All records rc 0, none
raised.

| App | B | BK | Y |
|---|---|---|---|
| Chrome probe page | pass (2/2 seen) | pass | pass |
| Mail new message | pass (2/2 seen) | pass | pass |
| VS Code (Electron) | **fail** (0/2 seen) | pass | pass |

So the P2b "read-back no" rows for these apps were read-back false negatives (the AX focused element is not the text
the keys reach), and the log's `→ probe terminal` labels here are false positives (token names restart per run and the
first run had printed them into the same iTerm scrollback). L3 selftests must not rely on AX read-back for Chromium,
Mail or Electron.

**P2 conclusion:** **Y passes all 8 apps** (TextEdit, TextEdit same-app, Safari, Slack, Terminal.app, Chrome, Mail,
VS Code) with no raise; B fails VS Code and raises Slack. L3 adopts Y (yabai v7.1.25 `focus_window_without_raise`).

## Decisions (operator, 2026-11-24: "go with your recommendation"; D3 "yes, and other command hotkeys")

- **D1 — v0.0.2 scope (decided: as proposed).** L2 (B1, B2, A2) was in the v0.0.2 batch plan but is blocked on probes. Proposed: v0.0.2 =
  L1 + F1 and merges now; L2 becomes L3 here. (Claude recommends.)
- **D2 — focus indicator (decided: option 1, border overlay).** (1) thin click-through border overlay around the focused window, config opt-out
  `focusIndicator: false` (Claude recommends); (2) menu-bar text with the focused app's name; (3) document only.
- **D3 — Safari Cmd+W and B2 priority.** P2 proposed for both (shortcuts silently go nowhere until a click). **Decided: P2, and the scope widens to every command hotkey** — P2 and
  the L3 selftest/live matrix check that Cmd-key shortcuts (Cmd+W, Cmd+T, Cmd+L, Cmd+N, Cmd+Q, Cmd+F, menu shortcuts)
  reach the hover-focused app in each app class, not only typed text.

## Gates

Per batch: worker report with mutant/red controls, Claude verify, land on `v0.0.3`. Release: Argon blind review of the
PR (hoverfocus is not a Copilot repo), CI green, operator live checks on m2 (app matrix rerun: focused yes and raised no
for every row; border follows focus; red status + one notification on a broken config; rebuild twice keeps the grant).
