# Review: lib-foundation PR #96 (v0.5.12 release) — blind diff review

**Filed:** 2026-11-27
**Repo / branch:** `lib-foundation` / `release/v0.5.12` (head 715dda0; diff `origin/main...715dda0 -- scripts docs CHANGE.md`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

`bin/k3dm-codex-dispatch start --spec docs/plans/release-lf-pr96-v0.5.12-review.md --repo ~/src/gitrepo/personal/lib-foundation --branch release/v0.5.12 --agent agy --model gemini-4-argon-medium --coordinator anthropic/claude-opus-5-5`

## Task

Review `git diff origin/main...715dda0 -- scripts docs CHANGE.md` blind. Copilot is capped until 2026-12-01, so this review is
the PR's review gate. The change claims: ACG sandbox SSH aliases (`ubuntu`, `ubuntu-<n>`) are written to a dedicated
fragment `~/.ssh/k3dm-sandbox.conf` instead of `~/.ssh/config`, through a new `scripts/lib/ssh_fragment.sh` (atomic temp
file + chmod 600 + move; refuses symlinked or dangling-symlink fragments on write and removal; stanza-bounded hostname
update; whole-alias removal; `ssh -G` effect check warning once). `acg_provision` requires an unconditional `Include` of the
fragment before any CloudFormation call (`K3DM_SSH_SANDBOX_INCLUDE=warn` downgrades); `acg_teardown` removes its aliases on
success paths only, a cleanup failure warns and keeps rc 0. Alias and IP values are passed to embedded Python as data.

Look for:
- the main `~/.ssh/config` (or its symlink target) being written or truncated on any path;
- a race or partial write that leaves a truncated fragment; a temp file left behind or created world-readable;
- symlink/TOCTOU gaps between the `-L` check and the write or removal;
- alias matching that removes the wrong stanza (prefix match `ubuntu` vs `ubuntu-1`, comments, `Host` lines with several names);
- the preflight passing when the Include is conditional (`Match`), commented, after a `Host` block, or uses `~`;
- injection: alias, IP, or path reaching shell or Python as code; unquoted expansions;
- `acg_teardown` return codes changed (it was at the 8-`if` audit limit);
- GNU-only flags or argument orders (the hub runs Homebrew bash 5 with BSD coreutils);
- tests that cannot fail (bare `! cmd` under `set -e`), touch the real `$HOME/.ssh`, call real ssh-to-network, AWS, sudo;
- CHANGE.md or `docs/api/acg.md` misdescribing the behaviour.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is 715dda0.
2. Read `scripts/lib/ssh_fragment.sh`, then the `acg.sh` diff (`git diff origin/main...715dda0 -- scripts/lib/acg/acg.sh`), then the tests.

## Files

| File | Change |
|---|---|
| every file in `git diff --name-only origin/main...715dda0 -- scripts docs CHANGE.md` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT use the network or run install functions for real; do not run sudo, launchctl, aws or ssh to a host.
- Do NOT read the real `~/.ssh` directory.
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
    intent: An independent model checks the lib-foundation v0.5.12 release code before you merge it, in place of Copilot this month.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** standing rule from "Copilot reach his cap ... you might want to have Argon for code review" (operator, 2026-11-17): release PRs get a blind Argon review until 2026-12-01. Intent text is the PR #164 review's, with the release named.
