## Current state 2026-11-20 07:31 PST — v1.45.0 open — START HERE

Older handoffs and logs, verbatim: `memory-bank/archive/activeContext-2026-11-20.md` (compressed 2026-11-20, operator ask).
Source of truth for open work: `docs/bugs/` `**Waiting on:**` lines, the dispatch ledger (`bin/k3dm-codex-dispatch open`),
and plan Status lines in `docs/plans/v1.45.0-*.md`.

**Branch:** `k3d-manager-v1.45.0`, everything pushed. Hub `deploy/hub` = `9d7973b6` (promoted 2026-11-20 07:21 PST,
tag hub-promote/20261120T152130Z); commits after it are docs-only, no promote needed.

**E9 approach (2026-11-20):** drain run by hand on a staged exited toy in a scratch root (overrides inline, never after `cd &&`); watcher->drain wiring owed to stall-recovery part 1.

**NEXT SESSION — operator agreed 2026-11-20 to do all three live checks, in this order:**
1. Child B E9/E10 (`docs/bugs/2026-11-14-dispatch-stall-b-approval.md`). Operator ran `/hermes-auth` 2026-11-20 07:29 PST
   (Slack: "Re-authenticated for 24h") -> valid until ~2026-11-21 07:29 PST; if later, ask for a fresh `/hermes-auth`.
   Claude stages a toy stalled dispatch so the stall watcher posts a card in #grafana-notification; operator presses
   Approve -> check resumed once (status running, resumes incremented, Slack confirm line) = E9. Second toy stall,
   operator presses Deny -> stays exited, authorised drain GET empty = E10. No card has been posted yet (none staged).
2. Child C E8 (`docs/bugs/2026-11-14-dispatch-stall-c-diagnose.md`): Claude already ran it on the M4 2026-11-19T03:12:49Z
   (PASS). Owed: print diagnosis.md + correction.md (M4 scratch root of that run) for the operator to judge, and the
   operator compares $0.052646 with the Anthropic Console. Then mark LIVE-VERIFIED.
3. Web-console part A E11–E14 (`docs/plans/v1.45.0-web-console-a-console-sshd.md` lines 722-775): operator at the keyboard
   with sudo, M4 then M5, ~30-45 min. Claude first prepares the throwaway CA + certs (good, other-CA, wrong principal,
   expired) and the part B scratch sshd enabled control, captures P2-P5, then reads redacted output. Order E11 -> E12 ->
   E13 -> E14 (E14 revoke last; uninstall removes the test CA). Also fix that plan's stale Status ("verify pending",
   verify is recorded).

**Dispatch WIP 0/3:**
- `remote-promote-2d-mover` VERIFIED b42cb927 + 2c6a4cc5, promoted in 9d7973b6; E11 live still owed.
- Next dispatches, each needs an operator go: web-console part C (`docs/plans/v1.45.0-web-console-c-totp-gate.md`), then
  remote-promote 2e (Makefile; file-disjoint otherwise). 2c then 2b follow 2d.

**Live checks owed:**
- Child B E9/E10: relay deployed by operator from the M4 2026-11-20 (version f02af9db, `[rd]` action IDs); M4 Keychain has
  drain token + slack webhook (pre-existing, not re-exported this run — if the drain gets 401/403, refresh from M5 with
  `security add-generic-password -U … -w`). M5 Hermes now has the `d` handling (promote 9d7973b6). `/hermes-auth` done
  2026-11-20 07:29 PST. Remaining: stage toy stalls, Approve (E9) / Deny (E10) — see NEXT SESSION above.
- Web-console part A E11–E14 (operator); child C E8 (M4); travel bundle E2/E3; test-all E3. Done 2026-11-20 after promote
  9d7973b6: hub-deploy self-update E2 LIVE-VERIFIED, velocity tile live (3 = v1.44.0/1/2).

**Captured this session (P3, grooming):** `docs/bugs/2026-11-19-web-console-sshd-no-set-euo-pipefail.md` (also: its BATS
file is 555 s, the slowest; GitHub SSH keepalive now in dotfiles `ssh/m4-air/config`),
`docs/bugs/2026-11-20-machine-setup-antigravity-cli-refuses-unowned-agy.md`. M4 lacks `gemini-cli-api-key` (operator-
supplied; machine-setup exits 1 until added).

**Other open:** dirused M9a E2 LIVE-VERIFIED 2026-11-20; M9b spec next — tracked outside k3d-manager
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
- 2026-11-20 06:49: CI green on 9d7973b6 (7/7). Promote SHA given to operator: 9d7973b62d04063c4af905da3909567fbcbaf596. Docs-only commits pushed after.
- 2026-11-20 07:23: promote 3d5fd9ef -> 9d7973b6 done by operator (tag hub-promote/20261120T152130Z; appsets-check ok, platform-ops ok, exporter rolled out). hub-deploy self-update E2 LIVE-VERIFIED from the pane. ArgoCD hub-grafana-dashboards still on 3d5fd9ef at 15:23Z (waiting on its poll) before checking the velocity tile.
- 2026-11-20 07:26: ArgoCD hub-grafana-dashboards synced 9d7973b6 on its own at 15:25:11Z (no refresh needed, ~3.5 min after promote). Velocity tile live: panel 34 Releases / 7 days, Prometheus count = 3 (v1.44.0, v1.44.1, v1.44.2); operator screenshot shows it.
- 2026-11-20 07:31: operator ran /hermes-auth 07:29 PST (24h). Handoff written; operator /clear next. Next session: child B E9/E10, child C E8 judgement, web-console A E11-E14.
- 2026-11-20 ~08:00: E9 staging incident: smartcd made `cd && export` skip the overrides, so toy `e9-toy-approve` started in the production root with the real Codex (gpt-6.1-terra); killed after ~15 s (143), worktree clean; abandoned (operator "go 0"); usage 45.9K in / 247 out in the production ledger. P3 filed: docs/bugs/2026-11-20-toy-dispatch-staged-in-production-root-real-codex.md. Finding: the stall watcher never calls the drain (child A N3; wiring = stall-recovery plan part 1, not written), so E9/E10 run the drain by hand; the watcher-driven half stays owed. Next: operator "go E9" (steps listed in session; all overrides inline).
- 2026-11-20 ~08:05: E9 card d1-9593afc1 posted (toy e9-approve, scratch root), but the drain cannot see clicks: Cloudflare 403 error 1010 on Python's default User-Agent (custom UA 200, wrong token 401). M4 drain token re-copied from M5 (works). P1 (operator) spec docs/bugs/2026-11-20-hermes-approvals-drain-blocked-by-cloudflare-user-agent.md; dispatch to Flash (gemini-3.8-flash-medium) after intent approval. Card left to expire 09:40 PST; E9 reruns on a fresh card after the fix lands. M5 Hermes approvals likely broken by the same path.
- 2026-11-20 ~08:15: dirused M9a E2 LIVE-VERIFIED (operator, jump box, v0.0.23): 2 held Tomcat85 redirect logs 'would delete after stopping Tomcat85', 11-03 log not held (plain would delete; spec expectation wrong, behaviour right), savelist/fromlist round trip same 3 rows. Plan Status fixed (offline VERIFIED 11-19 never recorded). Note for M9b: held file size from directory metadata was stale (117G -> 138G). Next: M9b spec.
- 2026-11-20 ~08:25: spec docs/plans/dirused-list-local-time.md (v0.0.24: delete list v2, lastWrite local time with offset + full fraction, v1 still read); operator asked to fold it into M9b and dispatch; Claude split it out because M9b is blocked (SEVERE-lines proof owed before its spec; medium risk = Fable + Astra review). Waiting on intent approval, then Flash/Luna (WIP 1/3).
- 2026-11-20 ~08:35: dirused-list-local-time dispatched to Flash (dirused branch list-local-time from 2ca49a2; ledger version v1.45.0, not v0.0.24). WIP 2/3 (P1 approvals UA + this).
- 2026-11-20: P1 approvals UA LANDED 970aeb23 (Sonnet verifier all pass); E4 live passed on M4 (no-UA 403 1010 vs UA 200; fetch_approvals empty queue). Pending E5: E9 fresh toy card + promote 970aeb23 for M5 Hermes. dirused list-local-time LANDED aa41dc0 (169/169, verifier mutants a-g red; CHANGELOG moved under Unreleased), PR wilddog64/dirused#37, Argon blind review running.
- 2026-11-20: dirused PR #37 merged 2e62aed, tag v0.0.24 (CI green, Argon clean). Pending operator E2 on jump box. P1 E5 pending: E9 toy card + promote 9c3345ba after CI.
