# HoverFocus v0.0.2 — bug batches (Flash / Luna split)

**Filed:** 2026-11-23
**Status:** plan — L1/F1 child specs rev 1 written ([L1](hoverfocus-v0.0.2-l1-app-lifecycle.md), [F1](hoverfocus-v0.0.2-f1-install.md)); `v0.0.2` cut on origin at `d426f18`; awaiting Fable spec review, operator intents and go. P1 probe also covers the Cmd-W/key-window gap (B2 recurrence) and Safari (`docs/hoverfocus/bugs/2026-11-23-hoverfocus-safari-no-focus.md`)
**Repo:** `hoverfocus`, branch `v0.0.2` cut from `main` at `d426f18` (v0.0.1)
**Approval:** "plan for bugs distributions between flash and luna" (operator, 2026-11-23)

Split rule (`feedback_split_large_specs_flash_luna`): Luna takes logic, Flash takes build/docs/shell; one dispatch per
file; a fix that depends on macOS behaviour gets a live probe first ("prove external behaviour before dispatch").

## Inputs

| Bug | Doc | Files |
|---|---|---|
| B1 same-app window switch | `docs/hoverfocus/bugs/2026-11-23-hoverfocus-same-app-window-switch-no-effect.md` | `Controller.swift`, `CSkyLight.c` |
| B2 terminal unfocused cursor | `docs/hoverfocus/bugs/2026-11-23-hoverfocus-iterm-hollow-cursor-after-no-raise-focus.md` | `Controller.swift`, `CSkyLight.c` |
| B3 install/TCC gaps (4 parts) | `docs/hoverfocus/bugs/2026-11-23-hoverfocus-install-launchagent-and-tcc-grant-gaps.md` | `Makefile`, `tests/install_test.sh`, `AppDelegate.swift` |
| A1 reload fails open | `docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md` #1 | `AppDelegate.swift` |
| A2 AX element cache leak | same, #2 | `Controller.swift` |
| A3 Makefile sed escaping | same, #3 | `Makefile` |

## Batches

| Batch | Worker | Scope | Files | Blocked on |
|---|---|---|---|---|
| **L1** | Luna | A1 (reload: on config error stop focusing, show error) + B3 part 3 (watch trust without a menu click: poll while untrusted, start the controller when granted) | `Sources/hoverfocus/AppDelegate.swift`, selftest | intent |
| **F1** | Flash | B3 parts 1-2 (bootout then wait before bootstrap; detect non-Aqua `launchctl managername` and print the `asuser` command instead of failing) + A3 (escape `APPDIR` for sed/XML) + B3 part 4 doc (print the `tccutil reset` step after install) + README | `Makefile`, `tests/install_test.sh`, `README.md` | intent |
| **P1** | Claude + operator (live) | probe for B1/B2: on m2, candidate ways to make a non-key window key without raising (AX `kAXMainAttribute`/`kAXFocusedAttribute` on the window, after variant B), record raise and terminal cursor | scratch probe only | operator at the m2 (from ~15:30) |
| **L2** | Luna | B1 + B2 from P1's winning variant, plus A2 (evict closed windows from `elements`) | `Sources/HoverFocusPlatform/Controller.swift`, `Sources/CSkyLight/*`, selftest | P1 |

### P1 app matrix (operator, 2026-11-24: "go ahead to add it")

Variant B is proven on TextEdit and iTerm2 only; Safari has now shown three behaviours (see the Safari bug, update
2026-11-24). P1 runs every app below with the pointer resting on an unfocused window behind iTerm2 and records three
things: **focused** (a typed key reaches it), **raised** (the window comes to the front) and **side effects** (popovers,
field focus, menu changes).

| App | States to try |
|---|---|
| Safari | page content; tab bar; new-tab page; address field focused before switching away |
| Chrome | page content; tab bar |
| Mail | message list; message body |
| Finder | file list; sidebar |
| Electron app (VS Code or Slack) | editor or message pane |
| Terminal.app, iTerm2 | prompt (cursor shape, B2) |
| TextEdit | document (control: proven no-raise 2026-11-24) |

Outputs:
1. The matrix table goes into the Safari bug doc and decides L2's design. If raises cluster in apps that take an
   address/search field on activation, L2 adds a per-app fallback: set `kAXMainAttribute` on the target window via AX
   **without** activating the app, and see whether that gives key focus with no raise. Otherwise apps that raise go to a
   documented default `ignoreApps` list.
2. README "Tested apps" table (focused / raised per app, macOS version, date), written by Flash in F1's README section,
   or a follow-up docs batch if F1 has already landed. F1 owns `README.md` for v0.0.2. Claude's interim Safari note
   (`dc68692`) went to `m1-base` by mistake. That branch was already merged as v0.0.1, so the note does not reach
   `v0.0.2`; F1 carries the corrected wording instead ("can raise", not "raises").
3. The operator E-L checks for L2 repeat the matrix rows. A must_not for L2: TextEdit and iTerm2 still focus with no raise.

L1 and F1 share no file and can run in parallel (WIP 2 of 3). L2 waits for P1. Stable local code signing (B3 part 4
fix) needs an operator decision on creating a local signing identity; until then F1 only prints the reset step.

## Gates per batch

Spec with Acceptance (`must_not` red on v0.0.1), Fable spec review (hoverfocus rule), worker, Claude verify with the
selftest + `tests/install_test.sh` under the sandbox-exec sudo/launchctl deny profile, blind Argon diff review, then
operator live E-L checks on m2 at home.
