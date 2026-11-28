# Review: k3d-manager PR #166 (v1.46.0 release), part a — cloud requests, approvals, routing — blind diff review

**Filed:** 2026-11-27
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0` (head 8bca3613; diff `origin/main...8bca3613 -- bin/k3dm-cloud-bridge bin/k3dm-cloud-request bin/k3dm-webhook bin/k3dm-webhook-doctor scripts/lib/webhook workers/slack-relay scripts/etc/launchd scripts/plugins/e2e_remote.sh`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff origin/main...8bca3613 -- bin/k3dm-cloud-bridge bin/k3dm-cloud-request bin/k3dm-webhook bin/k3dm-webhook-doctor scripts/lib/webhook workers/slack-relay scripts/etc/launchd scripts/plugins/e2e_remote.sh` blind, with the tests under `scripts/tests/` that exercise these files.
Docs and memory-bank are out of scope. Copilot is capped until 2026-12-01, so this review is the PR's review gate (with
part b). This pass is for **correctness**: a change that does not do what is described below, a failure that
reads as success, or a test that cannot fail. Report a security defect too if you see one. The intended behaviour is:

- **Approval gate** (`scripts/lib/webhook/cloud_approval.py`, `bin/k3dm-cloud-bridge`, `workers/slack-relay/index.js`): cloud-runner requests (`sandbox-up`, `sandbox-down`, `make-e2e`, `make-e2e-remote`) are held pending until an operator Approve or Deny on a Slack card; the first decision wins; a request never runs without an approval bound to that exact request; denials and expiries are final.
- **Watch ledger** (`bin/k3dm-cloud-bridge`): lines from the public `cloud-requests` branch are validated before use; watched output is scrubbed; lifecycle requests have an explicit timeout.
- **Notification routing** (`scripts/lib/webhook/notify_routes.py`, `lifecycle.py`, `bin/k3dm-webhook`): a request may name an approved alias; only aliases in the route map resolve; a routed job never falls back to another channel; an unrouted job keeps every notice in one thread; routed make output is escaped.
- **Helper process handling** (`scripts/lib/webhook/proc.py`, `bin/k3dm-cloud-request`): spawn falls back to `setpgroup=0` when `POSIX_SPAWN_SETSID` is unsupported, and the timeout still kills the whole tree.
- **Make target limits** (`scripts/lib/webhook/make_targets.py`): `test-bin` 4200 s, `test-all` 5400 s.

Look also for: unquoted shell expansions, input reaching a shell or `eval`; secrets in argv, logs or Slack text;
GNU-only flags (the hub runs Homebrew bash 5 with BSD coreutils); tests that cannot fail (bare `! cmd` in BATS),
touch the real `$HOME`, the real hub, network, sudo or launchctl.

## Before You Start

1. Confirm `git merge-base --is-ancestor 8bca3613 HEAD` succeeds (later commits are docs only); review the 8bca3613 diff.
2. Read the diff file by file, then the tests that cover each file.

## Files

| File | Change |
|---|---|
| every file in `git diff --name-only origin/main...8bca3613 -- bin/k3dm-cloud-bridge bin/k3dm-cloud-request bin/k3dm-webhook bin/k3dm-webhook-doctor scripts/lib/webhook workers/slack-relay scripts/etc/launchd scripts/plugins/e2e_remote.sh` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT use the network; do not run sudo, launchctl, kubectl, aws, ssh, or any make target that reaches a cluster.
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
    intent: "An independent model checks the v1.46.0 cloud-request, approval and routing code before you merge it, in place of Copilot this month."
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** standing rule from "Copilot reach his cap ... you might want to have Argon for code review" (operator, 2026-11-17): release PRs get a blind Argon review until 2026-12-01; v1.46.0 release PR #166 opened 2026-11-27 after the operator asked for it ("I think you can do 1, 2, 4, and 5!"). Intent text is the PR #165 spec's, version and part updated.
