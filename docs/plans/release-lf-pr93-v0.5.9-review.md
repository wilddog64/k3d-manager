# Review: lib-foundation PR #93 (v0.5.9 release) — blind diff review

**Filed:** 2026-11-23
**Repo / branch:** `lib-foundation` / `release/v0.5.9` (head 22250a3; diff `origin/main...22250a3 -- scripts docs CHANGE.md`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

`bin/k3dm-codex-dispatch start --spec docs/plans/release-lf-pr93-v0.5.9-review.md --repo ~/src/gitrepo/personal/lib-foundation --branch release/v0.5.9 --agent agy --model gemini-4-argon-medium --coordinator anthropic/claude-opus-5-5`

## Task

Review `git diff origin/main...22250a3 -- scripts docs CHANGE.md` blind. Copilot is capped until 2026-12-01, so this
review is the PR's review gate. The change claims to be a **behaviour-preserving refactor**: `_install_istioctl` in
`scripts/lib/core.sh` is split into five `_istioctl_*` helpers so no function has more than 8 `if` statements. The
intended behaviour, unchanged from v0.5.8:

- Pinned istioctl `${ISTIOCTL_VERSION:-1.31.4}`; an existing istioctl (install_dir first, then PATH) of the same minor
  is kept with no download; another minor, or an unparseable version line, is refused with one `_err` line.
- Otherwise download the release archive for osx/linux × amd64/arm64 with `curl -fsSL` into `mktemp -d`, verify the
  SHA-256 against `_istioctl_pinned_sha256`, extract, copy into install_dir (plain mkdir/cp when writable, else
  `_run_command --prefer-sudo`), re-check the installed binary's minor by full path.
- Every failure path removes the temp dir before `_err`; no global EXIT trap; no `cd`.

Look for:
- any behaviour difference from v0.5.8 (`git show origin/main:scripts/lib/core.sh`): a message, return code, order of
  checks, cleanup, sudo path, or a value a helper passes back through a global that can be stale or leak;
- a failure that becomes success (ignored helper return code, `|| true`, a subshell swallowing `_err`);
- quoting/injection: unquoted expansions, unvalidated version or path reaching curl, tar, cp or `_run_command`;
- tests that cannot fail (negated commands without `run !`, assertions on the wrong `run`), tests that write outside a
  temp dir, or call real sudo or network;
- CHANGE.md entries that misdescribe the change.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is 22250a3.
2. Read both versions of `_install_istioctl` and the five helpers, then the changed tests.

## Files

| File | Change |
|---|---|
| every file in `git diff --name-only origin/main...22250a3 -- scripts docs CHANGE.md` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT use the network or run install functions for real; do not run sudo or launchctl.
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
    intent: An independent model checks the lib-foundation v0.5.9 release code before you merge it, in place of Copilot this month.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** standing rule from "Copilot reach his cap ... you might want to have Argon for code review" (operator, 2026-11-17): release PRs get a blind Argon review until 2026-12-01. Intent text is the PR #164 review's, with the release named.
