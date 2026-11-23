# HoverFocus v0.0.2 — bug batches (Flash / Luna split)

**Filed:** 2026-11-23
**Status:** plan — L1/F1 child specs rev 1 written ([L1](hoverfocus-v0.0.2-l1-app-lifecycle.md), [F1](hoverfocus-v0.0.2-f1-install.md)); `v0.0.2` cut on origin at `d426f18`; awaiting Fable spec review, operator intents and go. P1 probe also covers the Cmd-W/key-window gap (B2 recurrence) and Safari (`docs/bugs/2026-11-23-hoverfocus-safari-no-focus.md`)
**Repo:** `hoverfocus`, branch `v0.0.2` cut from `main` at `d426f18` (v0.0.1)
**Approval:** "plan for bugs distributions between flash and luna" (operator, 2026-11-23)

Split rule (`feedback_split_large_specs_flash_luna`): Luna takes logic, Flash takes build/docs/shell; one dispatch per
file; a fix that depends on macOS behaviour gets a live probe first ("prove external behaviour before dispatch").

## Inputs

| Bug | Doc | Files |
|---|---|---|
| B1 same-app window switch | `docs/bugs/2026-11-23-hoverfocus-same-app-window-switch-no-effect.md` | `Controller.swift`, `CSkyLight.c` |
| B2 terminal unfocused cursor | `docs/bugs/2026-11-23-hoverfocus-iterm-hollow-cursor-after-no-raise-focus.md` | `Controller.swift`, `CSkyLight.c` |
| B3 install/TCC gaps (4 parts) | `docs/bugs/2026-11-23-hoverfocus-install-launchagent-and-tcc-grant-gaps.md` | `Makefile`, `tests/install_test.sh`, `AppDelegate.swift` |
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

L1 and F1 share no file and can run in parallel (WIP 2 of 3). L2 waits for P1. Stable local code signing (B3 part 4
fix) needs an operator decision on creating a local signing identity; until then F1 only prints the reset step.

## Gates per batch

Spec with Acceptance (`must_not` red on v0.0.1), Fable spec review (hoverfocus rule), worker, Claude verify with the
selftest + `tests/install_test.sh` under the sandbox-exec sudo/launchctl deny profile, blind Argon diff review, then
operator live E-L checks on m2 at home.
