# Review: lib-foundation PR #94 (v0.5.10 release) — blind diff review

**Filed:** 2026-11-24
**Repo / branch:** `lib-foundation` / `release/v0.5.10` (head af33f98; diff `origin/main...af33f98 -- scripts docs CHANGE.md`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

`bin/k3dm-codex-dispatch start --spec docs/plans/release-lf-pr94-v0.5.10-review.md --repo ~/src/gitrepo/personal/lib-foundation --branch release/v0.5.10 --agent agy --model gemini-4-argon-medium --coordinator anthropic/claude-opus-5-5`

## Task

Review `git diff origin/main...af33f98 -- scripts docs CHANGE.md` blind. Copilot is capped until 2026-12-01, so this review is
the PR's review gate. The change claims: `_istioctl_client_version` in `scripts/lib/core.sh` now runs
`istioctl version --remote=false` once (previously `version --short`, falling back to a bare `version`; both contact the
cluster and can hang when KUBECONFIG names a missing or unreachable cluster). Parsing of the first stdout line
(`^client version: X.Y.Z`, else `unknown`) and every caller are unchanged. Tests make every istioctl stub answer only for
exactly `version --remote=false` and add a timeout-bounded unreachable-cluster case.

Look for:
- any behaviour difference beyond the probe arguments: parsing, the `unknown` path, the refusal message, return codes,
  either caller (`core.sh` existing-istioctl check and post-install check);
- a failure that becomes success (`|| true` hiding a real error, a subshell swallowing `_err`);
- quoting/injection of `$path`;
- tests that cannot fail, tests whose timeout cannot fire or can hang the suite, tests that write outside a temp dir or call
  real sudo, network or istioctl;
- CHANGE.md entries that misdescribe the change.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is af33f98.
2. Read `_istioctl_client_version` on both sides (`git show origin/main:scripts/lib/core.sh`), its two callers, then the changed tests.

## Files

| File | Change |
|---|---|
| every file in `git diff --name-only origin/main...af33f98 -- scripts docs CHANGE.md` | read only |

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
    intent: An independent model checks the lib-foundation v0.5.10 release code before you merge it, in place of Copilot this month.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** standing rule from "Copilot reach his cap ... you might want to have Argon for code review" (operator, 2026-11-17): release PRs get a blind Argon review until 2026-12-01. Intent text is the PR #164 review's, with the release named.
