## Handoff — 2026-11-21 17:00 PST (01:00Z) — 2c and P3 landed; web-console C resumes after Codex reset 12:35 — START HERE

**Objective (next session):** finish the v1.45.0 dispatch queue, then the red-team gate, then the release PR.

**Session update 2026-11-21 12:25 PST:**
- 2c LANDED `c17eae59` (plan LANDED `32f05e79`, pushed). Resume 9 N1 fix verified by Claude: pytest 90/90, bats 9/9;
  env-socket mutant red in `test_main_reads_no_environment` (scratch copy). First land failed on an unrelated race,
  captured P3 `docs/bugs/2026-11-21-hub-deploy-bats-catch-up-test-races-git-index-lock.md` (`0c999bbe`); retry green.
- Password-bundle Keychain P3 LANDED `3971fa3f`. Verified: bats 15/15; mutants red (password on argv → 15, any rc
  diagnosed → 14, unlocked still unlocks → 13, one invalid message → 4,11); 7 tests red on pre-fix plugin.
- web-console C r2: resume 4 hit Codex usage limit 12:08 mid-evidence (empty last-message-4). Partial tree (11 files)
  uncommitted in the r2 worktree; backup `/private/tmp/claude-501/-Users-cliang-src-gitrepo-personal-k3d-manager/517093b8-70e9-4015-947e-2c827b62535f/scratchpad/c-r2-resume4-partial.tgz`.
  Spec contract = `## v6 changes` (`0f07641a`). Resume 5 (12:36) hit the Codex limit again 12:59; next reset 17:36 PST.
  Tree now pytest 126 / bats 25 green, mutant table and final gates not done; backup
  `/private/tmp/claude-501/-Users-cliang-src-gitrepo-personal-k3d-manager/517093b8-70e9-4015-947e-2c827b62535f/scratchpad/c-r2-resume5-partial.tgz`. Independent Sonnet verifier (Acceptance only, scratch
  copy, no sudo) running now; its gaps go into resume 6 at 17:36 with the mutant table.
- Offline test-all P2 rechecked by Claude (no dispatch needed): C3/C4 fixed, C1/C2 latent (env masks them);
  bug doc `af2cc5d9` → Waiting on operator decision, grooming 11-22. Stale bugs closed `0e08dac4`. All pushed.
- agy quota question answered: token sums per pool from conversation DBs are buildable; % needs calibration from the
  agy panel or an operator-approved probe; fold into `docs/plans/argon-bug-classifier.md` at grooming.
- Operator applied the LAST Codex reset credit (none left); asked to split remaining C work across Flash and Luna.
  Independent verifier mutant table so far: 126/168 run, 103 red, 23 GREEN survivors (D4b D11b D13 D27 D18 D30 D31
  D31b D31c D40 D44 G9b G20 G20c G27 G40 C10 B11 B11b B14 B22 B25b B34). Flash (gemini-3.8-flash-medium, ad hoc,
  read-only, snapshot copy `scratchpad/flash-audit/tree`) writing AUDIT.md: acceptance-id → test coverage + howto drift.
  Next: when verifier + Flash finish, one `resume --slug web-console-c-totp-gate-r2 --model gpt-6-luna` with all
  survivors + Flash gaps (children cannot branch off the uncommitted r2 tree; dispatcher bases on the release branch).
- Flash audit done (`scratchpad/flash-audit/tree/AUDIT.md`): 38 covered / 2 weak (M11, E9 doc greps) / 2 none
  (E10, E11 are live, expected). Docs drift: #1 false; #2 (rotate-pending → purge advice) and #3 (exit 8 "naming
  the path") real. Luna resume 6 RUNNING (`resume-6.md`): 23 survivors with exact mutation strings + 2 doc fixes.
  Verifier DONE: 162/168 run; clean tree 126 pytest / 25 bats; main checkout clean. Late survivors C3 (secret to temp
  file, security), G25, G35, B18 + 4 impl-vs-contract notes (tmux env 6 keys vs five, uninstall two commits vs one,
  --tmux symlink unresolved, E2 case 1 sequential) queued in `resume-7.md` for after Luna exits. Not run: B27 B30 B33
  B36 B39 G8 → Claude runs them on the final tree. D13 was a no-op mutant (ignore).
- Luna resume 6 done 15:04: 19/23 killed; equivalents D13, G9b, D40 accepted by Claude; D27 challenged (pending-slot
  test). pytest 137; bats 29/30 (test 11 order-dependent leak). Resume 7 RUNNING (C3/G25/G35/B18, 4 contract notes,
  bats leak, D27). After it: Claude reruns full mutant table + 6 unrun, commits, lands.
- Luna resume 7 done 15:45: C3 G25 G35 B18 D27 killed; env 5 keys + fixed PATH; uninstall one commit; --tmux realpath;
  bats leak was sandbox /dev/tty. Claude verify: pytest 140 passed, bats 31/31 (run 1); full 168-mutant rerun on final
  tree running in `scratchpad/cverify2` (3 workers).
- agy quota calibration point 1 recorded in `docs/plans/argon-bug-classifier.md` (Gemini 5h ≈13.0M, weekly ≈32.6M
  tokens est.; windows start at first call; Argon separate weekly). More points wanted later.
- Open dispatches 1 of 3: `web-console-c-totp-gate-r2`.

**State at handoff:**
- Branch `k3d-manager-v1.45.0` pushed. Hub `deploy/hub` = `42176488`; not yet on the hub: travel bundle rev 2 `39a24a59`,
  2c `c17eae59`, P3 `3971fa3f`.
- Quotas: Codex 5h exhausted until 12:35 PST (weekly 0.22 earlier); Fable weekly 0.08; Claude weekly 0.15. Warn at 0.80.
- Travel bundle: m2-air PASS; m4-air rc 36 → now gets the unlock prompt (P3); operator retry pending.

**Waiting on the operator:**
- `make hub-sync` then `make hub-deploy REF=<release head>` (rev 2, 2c, P3 onto the hub).
- m4-air `make password-bundle-show` retry (should now prompt to unlock the Keychain).

**Next, in order:**

1. **web-console C r2 — resume 5, verify, land.** Worktree
   `/Users/cliang/.local/share/k3d-manager/worktrees/v1.45.0/web-console-c-totp-gate-r2`; spec
   `docs/plans/v1.45.0-web-console-c-totp-gate.md` (Handover run 2 + v6 changes). Verify every E1-E11 item and mutant,
   independent verifier from Acceptance only, Claude commits, `land --slug web-console-c-totp-gate-r2`.
2. **2b and web-console B** (`docs/plans/v1.45.0-remote-promote-2b-promote-wiring.md`,
   `docs/plans/v1.45.0-web-console-b-captures.md`) — 2c has landed, so both can dispatch now (WIP ≤ 3, one per file;
   check file overlap with C r2: Makefile).
3. **Red-team gate** (`docs/plans/v1.45.0-red-team-gate.md`, intents approved) after 2b, B, C land; then the release PR
   (Copilot capped until 12-01, Argon reviews).
5. **Live checks owed (operator):** 2d E11; travel bundle E3 (next real rotation) and rev 2 E5 (first `add-laptop` after a
   hub-deploy); test-all E3; dispatch-stall C E8 and B E9/E10; dirused M9b E2 Mon 11-23 (office); web-console part A E12
   forwarding control; m4-air password-bundle-show after unlock.
6. **Grooming Sun 11-22** — say "triage due" at session start; agenda below.

**Known agent failure modes to check on every exit:** Codex sandbox cannot commit (Claude commits on the task branch);
agy/Codex report green suites they did not run; worker cd failures can delete untracked files in the main checkout
(`git status` there after each verifier run).

**Standing facts:**
- **Handoff guard:** `.claude/hooks/handoff-on-clear.sh` reports STALE if commits land after this header; bump the
  timestamp on any edit.
- **Older handoffs and the full 11-20/11-21 log:** `memory-bank/archive/activeContext-2026-11-21.md`.
- **Source of truth for open work:** `docs/bugs/` Waiting-on lines, `bin/k3dm-codex-dispatch open`, plan Status lines.
- **Carried small items:** ask-bash linked-worktree P3 unfiled; revoke the zshenv GitHub token; nit: SHA-256 pin in
  agent_dispatch_dashboard.bats test 54; locked-Keychain WARNs in hub-deploy; M2 `~/.ssh/config` is a copy, not a
  symlink (ask before changing).

## Grooming 2026-11-22 agenda
- New DRAFT `docs/plans/agy-quota-dashboard.md` (parent + Luna reader child + Flash dashboard child): place in backlog, approve intents, answer its 5 open questions (esp. which machines run agy). Revised same evening: brain transcripts carry per-step time+model+tokens; Agent Activity agy row exists but repo/mode are always `unknown` — plan now fills them and adds tokens by repo/model. Note Argon API rate rises 2026-12-01 (price file single-rate).
- Offline test-all P2 (`2026-11-09-offline-test-all-red-on-m4-four-root-causes.md`): close C3/C4; C1/C2 → one P3 or close. agy usage reader + calibrated % gauge into argon-bug-classifier plan. hub_deploy.bats race P3: v1.45.0 or later (10-P3 cap).
- Pull `docs/plans/v1.51.0-bug-count-query-translation.md` forward into the next open minor, displacing a not-started plan (operator 2026-11-17 "sounds good"); triage `docs/bugs/2026-11-17-ask-docs-list-wording-answers-old-release.md` with it.
- Ideas rows 2026-11-17 (Task Forest): dispatch-ledger reconcile + review-child folding; one "needs you" view.
- Ideas rows 2026-11-16/17: Claude-API reviewer, Claude-API Hermes writer.
- How to manage out-of-band repos (dirused and other work-environment tools): no ideas backlog, direct spec + dispatch for now; decide tracking, ledger and dispatch home (operator 2026-11-17). Add: per-project workload/quota metrics (agent tokens per repo from session logs + dispatch ledger), since dirused shares the weekly quota and was hand-counted (operator 2026-11-19 "yes").
- P3s from 2026-11-21: Sessions-by-mode Value bar, hermes e2e PASS line hides skipped, host-disk Free panel always red, hub-deploy tool preflight, ACG ssh hosts in tracked config, web-console host-key warning noise. Suggest moving plan 6 to v1.46.0.
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

- 2026-11-21: memory-bank compressed; full log archived to `memory-bank/archive/activeContext-2026-11-21.md`.
