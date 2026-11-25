# HoverFocus v0.0.3 — plan

**Filed:** 2026-11-24
**Status:** plan — D1-D3 decided (operator, 2026-11-24); P3 PASS (2026-11-25); next: P2 probe on m2, then child specs and Fable spec review
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
| **U1** | Luna | Visible errors: status line in red (attributed title); one Notification Center message on each transition into an error (config invalid, event tap, Accessibility lost), none while it persists | `Sources/hoverfocus/AppDelegate.swift`, `Sources/hoverfocus/MenuModel.swift`, selftest | P3 (notification permission needs the stable identity) |
| **U2** | Luna | Focus indicator per D2 | new `Sources/hoverfocus/FocusIndicator.swift`, one hook in `Controller.swift` | L3 (shares `Controller.swift`) |

Order: P2 and P3 together (one m2 session) → L3, F2, U1 in parallel (no shared file, WIP 3) → U2 after L3 lands.
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
