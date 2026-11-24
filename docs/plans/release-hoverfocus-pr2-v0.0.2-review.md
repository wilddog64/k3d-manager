# Review: hoverfocus PR #2 (v0.0.2 release) — blind diff review

**Filed:** 2026-11-24
**Repo / branch:** `hoverfocus` / `v0.0.2` (head 42273f0; diff `origin/main...42273f0`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

`bin/k3dm-codex-dispatch start --spec docs/plans/release-hoverfocus-pr2-v0.0.2-review.md --repo ~/src/gitrepo/personal/hoverfocus --branch v0.0.2 --agent agy --model gemini-4-argon-medium --coordinator anthropic/claude-opus-5-5`

## Task

Review `git diff origin/main...42273f0` blind. hoverfocus is not a Copilot repo, so this review is the PR's review gate.
The intended behaviour:

- **L1** (`Sources/HoverFocusCore/AppCoordinator.swift`, `Sources/hoverfocus/AppDelegate.swift`, selftest): on Reload
  Config, an invalid file stops the controller, keeps the last valid config and shows `Error: config <path>: <reason>`;
  a valid file applies and starts it. While Accessibility is untrusted a 2 s timer polls trust and starts the
  controller once granted (unless a config error is showing); the timer stops when trusted.
- **F1** (`Makefile`, `tests/install_test.sh`, `README.md`, `docs/config.md`): `make install` boots out the agent and
  waits (bounded by `BOOTOUT_WAIT_TRIES`) until it is gone before `bootstrap`, refusing if still loaded; when
  `launchctl managername` is not `Aqua` it installs files and prints the `sudo launchctl asuser` commands, exit 0;
  `APPDIR`/`AGENTDIR` are escaped so paths with spaces, `&`, `/` or XML characters are safe; ad-hoc builds print the
  `tccutil reset` hint.

Look for:
- a failure that becomes success, or a state where focus keeps running after an invalid config, or never restarts
  after a valid one or after trust is granted; a timer that never stops or is started twice;
- toggling Enabled / icon style (`coordinator.update`) while a config error shows: does it restart focusing or clear
  the error wrongly?
- Makefile quoting/injection with odd `APPDIR`/`AGENTDIR` values; the bootout wait loop's bound and the refuse path;
  anything that runs a real `launchctl` or `sudo` from tests;
- tests that cannot fail (negated commands without a real assertion, assertions on the wrong output), tests writing
  outside a temp dir;
- README/docs statements that misdescribe the behaviour.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is 42273f0.
2. Read the full diff, then `AppCoordinator.swift`, `AppDelegate.swift` and the `install` target in full.

## Files

| File | Change |
|---|---|
| every file in `git diff --name-only origin/main...42273f0` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT run `make install`, `launchctl`, `sudo`, `tccutil` or the built app; no network.
- Do NOT update any memory-bank.

## Definition of Done

- [ ] Report back one line per finding: `file:line — defect — concrete failure scenario — severity (high/medium/low)`.
      If there are none, report `no findings`. Mark each finding as verified-from-code or speculative.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report lists findings or "no findings"
    intent: An independent model checks the HoverFocus v0.0.2 release code before you merge it.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** standing rule from "Copilot reach his cap ... you might want to have Argon for code review" (operator, 2026-11-17) and CLAUDE.md PR merge gate (non-Copilot repos get a blind Argon review). Intent text is the PR #164 review's, with the release named.
