# Review: hoverfocus PR #1 (M1 prototype, v0.0.1) — blind diff review

**Filed:** 2026-11-23
**Repo / branch:** `hoverfocus` (`/Users/cliang/src/gitrepo/personal/hoverfocus`) / `m1-base` (head a4d9abb; diff
`git -C /Users/cliang/src/gitrepo/personal/hoverfocus diff origin/main...a4d9abb -- Sources Makefile packaging tests .github`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review
**Approval:** standing rule (operator, 2026-11-15/16): PRs that do not get Copilot get a blind Argon diff review,
verified by Claude; ship decision "ship v0.0.1 and fix bugs in v0.0.2" (operator, 2026-11-23)

## Task

The code under review is in the sibling repo `/Users/cliang/src/gitrepo/personal/hoverfocus`. Read it there with
`git -C <that path> diff` / `show` / `cat` only; do not cd into it to write anything. Review the diff above blind,
for **correctness**: a feature that does not do what is described below, a failure that reads as success, or a test
that cannot fail. Report a security defect too if you see one. README, LICENSE and docs are out of scope.

Intended behaviour:

- **HoverFocus** is a macOS menu-bar app (Swift). A listen-only CGEvent tap watches pointer movement; when the pointer
  rests (`stillnessPx`, `dwellMs`) over a standard window of another app, it focuses that window **without raising
  it**, via `_SLPSSetFrontProcessWithOptions(psn, wid, 0x400)` (`Sources/CSkyLight/CSkyLight.c`, resolved with
  `dlsym`). It never posts event records.
- **Engine** (`Sources/HoverFocusCore/Engine.swift`): pure logic; no decision while a button is down (if
  `ignoreWhenButtonDown`), with the pause modifier held, over a menu or Mission Control, for `ignoreApps`, for
  non-standard windows, or for the already-focused window; fires once per window until the pointer leaves it;
  `raiseApps` get focus-and-raise.
- **ConfigLoader** (`ConfigLoader.swift`): strict JSON at `~/.config/hoverfocus/config.json`; unknown keys or bad
  types are errors, not silently defaulted.
- **Controller** (`Sources/HoverFocusPlatform/Controller.swift`): start refuses unless Accessibility is trusted, the
  private symbol resolves and an event tap can be created; re-enables the tap after timeout/user-input disable;
  pause stops decisions.
- **App shell** (`Sources/hoverfocus/*`): menu shows Running / the failing start check; Grant Accessibility; pause
  30 min; reload config; menu-bar icon modes.
- **Install** (`Makefile`, `packaging/*`, `tests/install_test.sh`): builds the .app into `~/Applications`, renders the
  LaunchAgent plist, bootstraps it into `gui/<uid>`.
- **Selftest** (`Sources/hoverfocus-selftest/main.swift`): engine and config tests run in CI.

Known and already filed (do not report again): same-app window switch has no effect; terminals show an unfocused
cursor after hover focus; install over SSH fails with bootstrap error 5, an error-37 race on reinstall, the grant is
noticed only through the menu's Grant item, and ad-hoc signing invalidates the grant per build.

Look for:
- a failure path that reports Running or success when the tap, symbol or trust check failed;
- engine conditions that can fire focus while a button is down, on the focused window, repeatedly, or on ignored apps;
- config parsing that accepts invalid input or silently drops a key;
- unsafe pointer/CF handling in Controller or CSkyLight (unbalanced retain/release, unchecked `dlsym`, wrong types);
- Makefile/plist/install shell: unquoted expansions, writes outside `~/Applications`/`~/Library/LaunchAgents`, `sudo`;
- selftest or `tests/install_test.sh` checks that cannot fail, or that touch the real HOME, launchctl or TCC.

## Before You Start

1. `git -C /Users/cliang/src/gitrepo/personal/hoverfocus log --oneline -1 origin/m1-base` shows a4d9abb.
2. Read the changed hunks, then enough of each surrounding function to judge them.

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR, in either repo.
- Do NOT build or run the app, `make install`, launchctl, sudo, tccutil or any network call; reason from the code.
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back one line per finding: `file:line — defect — concrete failure scenario — severity (high/medium/low)`,
      marked verified-from-code or speculative. If there are none, report `no findings`.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario
must_not:
  - id: N1
    text: the reviewer changes any file in either repo
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree and in hoverfocus is empty; report lists findings or "no findings"
    intent: An independent model checks the HoverFocus v0.0.1 code before you merge it.
interface: none
```

**Intent approved:** operator, 2026-11-15 (standing rule: non-Copilot PRs get a blind Argon diff review)
**Approval words and scope:** "ship v0.0.1 and fix bugs in v0.0.2" (operator, 2026-11-23); this review gates hoverfocus PR #1.
