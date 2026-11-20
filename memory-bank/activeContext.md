## Current state 2026-11-20 ~06:40 PST — v1.45.0 open — START HERE

Older handoffs and logs, verbatim: `memory-bank/archive/activeContext-2026-11-20.md` (compressed 2026-11-20, operator ask).
Source of truth for open work: `docs/bugs/` `**Waiting on:**` lines, the dispatch ledger (`bin/k3dm-codex-dispatch open`),
and plan Status lines in `docs/plans/v1.45.0-*.md`.

**Branch:** `k3d-manager-v1.45.0`; origin at `776dcea0` (CI was in progress); local commits `9fdebf66`, `30fea88a` and this
compression not yet pushed (batched until 2d lands). Hub `deploy/hub` = `3d5fd9ef`; promote after 2d lands and CI is green
(operator runs `make hub-deploy REF=<sha>` in their tmux; K3dmPromoteWaiting/DeployPending alerts are the expected nudge).

**Dispatch WIP 1/3:**
- `remote-promote-2d-mover` VERIFIED b42cb927 + 2c6a4cc5 (6 verifier gaps closed, Claude re-ran mutants). WIP 0/3.
  (M9 absent tag after real update must be push_unknown [Claude reproduced], M9 `!` flag with exit 0, M10 fresh
  already_spent must not note_refusal, M5 merge-ancestor, M1 `--no-tags`, M13 min(default, remaining)). Correction
  resume 4 (tests only, prompt in session scratchpad `2d-resume4.md`) running, pid 81277. Next: verify each gap mutant is red,
  record verify (pre-fix = be8bff34^, delete-module rc 2), land, push, give promote SHA.
- Next dispatches, each needs an operator go: web-console part C (`docs/plans/v1.45.0-web-console-c-totp-gate.md`), then
  remote-promote 2e (Makefile; file-disjoint otherwise). 2c then 2b follow 2d.

**Live checks owed:**
- Child B E9/E10: relay deployed by operator from the M4 2026-11-20 (version f02af9db, `[rd]` action IDs); M4 Keychain has
  drain token + slack webhook (pre-existing, not re-exported this run — if the drain gets 401/403, refresh from M5 with
  `security add-generic-password -U … -w`). No webhook/Hermes restart needed (M5 Hermes ignores `d` IDs until promote).
  Remaining: operator `/hermes-auth` (24h), then Claude stages a toy stalled dispatch; Approve resumes once (E9), Deny
  leaves it exited and the relay queue empty (E10).
- Web-console part A E11–E14 (operator); child C E8 (M4); travel bundle E2/E3; test-all E3; hub-deploy self-update E2,
  dashboard panels and velocity tile after the next promote.

**Captured this session (P3, grooming):** `docs/bugs/2026-11-19-web-console-sshd-no-set-euo-pipefail.md` (also: its BATS
file is 555 s, the slowest; GitHub SSH keepalive now in dotfiles `ssh/m4-air/config`),
`docs/bugs/2026-11-20-machine-setup-antigravity-cli-refuses-unowned-agy.md`. M4 lacks `gemini-cli-api-key` (operator-
supplied; machine-setup exits 1 until added).

**Other open:** dirused E2 read-only run on the jump box (operator; v0.0.23), then M9b spec — tracked outside k3d-manager
releases. MEMORY.md over budget (compressing 2026-11-20). Triage due at grooming.

## Grooming 2026-11-22 agenda
- Pull `docs/plans/v1.51.0-bug-count-query-translation.md` forward into the next open minor, displacing a not-started plan (operator 2026-11-17 "sounds good"); triage `docs/bugs/2026-11-17-ask-docs-list-wording-answers-old-release.md` with it.
- Ideas rows 2026-11-17 (Task Forest): dispatch-ledger reconcile + review-child folding; one "needs you" view.
- Ideas rows 2026-11-16/17: Claude-API reviewer, Claude-API Hermes writer.
- How to manage out-of-band repos (dirused and other work-environment tools): no ideas backlog, direct spec + dispatch for now; decide tracking, ledger and dispatch home (operator 2026-11-17). Add: per-project workload/quota metrics (agent tokens per repo from session logs + dispatch ledger), since dirused shares the weekly quota and was hand-counted (operator 2026-11-19 "yes").
- P3s from 2026-11-18/19/20: run_parallel claim loop + file-lock signal cleanup (lib-foundation), web-console sshd `set -e` + slow BATS, machine-setup antigravity-cli, promote-to-dashboard lag, tokens-by-repo scratchpad label, plan-dashboard child specs.

## Standing rules (current)

- M5 is the hub; M4 is the dev node and this session's host (its kube context is dead: query the M5 over ssh).
- Every fix: Claude reviews the diff, independent verifier from the Acceptance block only (mutants per must_not, pre-fix
  red), Claude reproduces at least the top gap, land alone, then record. Record verify only from evidence captured now.
- Luna's sandbox has no network: put any upstream-source fact into the spec with its citation; never ask the worker to fetch.
- Push batching: each push cancels the in-flight CI run; push once per batch, then wait for green before giving a promote SHA.
- Fresh shells need `export SSH_AUTH_SOCK=/var/run/com.apple.launchd.uw3bpQR945/Listeners` to push; `cd` is broken by
  smartcd (use `git -C`, absolute paths, or `(builtin cd …)`).

## Dispatcher task closeout — standing workflow

When the operator asks to dispatch a bug and verify/land it, carry the task through these steps without asking for separate prompts: (1) inspect the task's accepted diff against its spec and confirm the worker exited; (2) independently run focused tests plus relevant regression suites, syntax/lint checks, `git diff --check`, and `_agent_audit` (ShellCheck only applies to shell files); (3) if the worker left reviewed changes uncommitted, commit them on its isolated task branch; (4) run `bin/k3dm-codex-dispatch land --slug <slug> --test '<focused gates>' --allow-out-of-scope` only when any scope exceptions are explicitly allowed, otherwise stop and resolve scope; (5) push the release branch to origin; (6) update the canonical bug and memory-bank to `VERIFIED` with commit SHA and actual test results; (7) stop short of `LIVE-VERIFIED` until the operator supplies live evidence, and proactively give them the exact safe live check and ask them to report/screenshot its outcome. Once live evidence arrives, update the bug/memory and push that status change. `VERIFIED` means offline gates passed and fix is landed; `LIVE-VERIFIED` requires operator evidence from the deployed system.

If a local-server suite fails only because the sandbox cannot bind localhost, report that distinction and rerun with the required approved permission before judging the fix. Never infer live success from offline tests or let a passed offline test alone change status to `LIVE-VERIFIED`.

## Log
- 2026-11-20 (morning): memory-bank compressed (operator ask): activeContext 165K -> ~8K, progress 81K -> ~4K; verbatim copies in archive/*-2026-11-20.md. 2d correction 412e59be (91 tests); Claude reran 6 gap mutants, all killed.
- 2026-11-20 (morning): 2d LANDED b42cb927 + 2c6a4cc5, VERIFIED (verify recorded). WIP 0/3. Push then promote after CI green.
- 2026-11-20 (morning): MEMORY.md 9063 -> 8662 bytes (3 pointers moved into hub_projects / hub_ref_observability, one line shortened; no pointer lost, no memory wrong or expired). Sonnet trial lines logged in progress.
- 2026-11-20 (morning): ideas row added (memory-bank size budget + /post-merge 7c recipe), operator ask.
- 2026-11-20 (morning): 3 ideas rows for grooming (rework_ratio + operator time, required reviewed field, weekly live-check slot), operator ask.
- 2026-11-20 (morning): CI lint red on 82d105e4 (6 pyflakes: 2 unused datetime imports in bin/k3dm-dispatch-recover from child B, 4 in test_promote_mover.py from Luna 412e59be). Claude miss: linted 2d before the correction and never ran pinned ruff on child B. Fixed (claude_edit after land); lint clean, 91 + 18 tests pass.
- 2026-11-20 (morning): "other" in Tokens by repo traced (6.45 M = one dispatch whose worktree version v1.44.0 differs from its ledger version v1.44.1); appended to the tokens-by-repo P3.
