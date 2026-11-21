## Handoff — 2026-11-21 12:20 PST (20:20Z) — memory compressed before /clear; 2c and web-console C wait for Claude — START HERE

**Objective (next session):** finish the v1.45.0 dispatch queue, then the red-team gate, then the release PR.

**Session update 2026-11-21 11:55 PST:**
- 2c: all 12 resume-8 items verified present in the wip; rebased onto release head → task HEAD `4adcb0e2` (backup tag
  `backup/2c-pre-rebase-419b34c1`); Makefile merge additive; pytest 89/89, bats 9/9, shellcheck clean. Independent Sonnet
  verifier done: 14/14 must_not red on mutants, pre-fix reds match; gap N1 (env guard is a literal grep, two env mutants
  green). Correction resume 9 (Codex astra, test-only AST scan + hostile-env main()) running.
- web-console C: static gates pass, suites green (14 pytest, 7 bats), but coverage is far short of E2-E8 (no real-pty/
  scratch-tmux gate tests, E8 installer fixture absent, no mutants). Operator chose Codex astra: Flash run committed
  `567faa63` (tag `backup/web-console-c-flash-run1`), agy slug abandoned, plan gained `## Handover (run 2, Codex)` (`d17e565b`),
  new dispatch `web-console-c-totp-gate-r2` (gpt-6.2-astra). Run 1 stopped on a real spec hole (uninstall 7.2 vs 7.6/M9 when
  bootout fails); spec fixed `790afd26`; resume 2 applied the Flash draft and stopped on part A exit-3 (CA missing) row count: spec
  now refuses it (`d9599ad0`); resume 3 (one full review pass) found 7 more, incl. Claude's own d9599ad0 row-count bug; all resolved in
  `## v6 changes` (`0f07641a`); resume 4 running to completion. Codex cannot commit: Claude commits on exit.
- Intents approved (operator 2026-11-21): password-bundle Keychain P3 and red-team gate (`20a6580f`). P3 dispatched as
  `password-bundle-keychain-next-step` (Codex astra). WIP 3 of 3: 2c (verifier running), C-r2, P3.

**State at handoff:**
- Branch `k3d-manager-v1.45.0`, everything pushed. Hub `deploy/hub` = `42176488` (2026-11-21 08:16 PST); commits after it
  that matter on the hub: travel bundle rev 2 `39a24a59` (needs a hub-deploy for `make password-bundle-add-laptop`).
- Open dispatches 2 of 3 (`bin/k3dm-codex-dispatch open`): `remote-promote-2c-root-daemon` (wip `419b34c1` on its task
  branch, Codex resume-8 partial) and `web-console-c-totp-gate` (agy Flash exited 0, uncommitted in its worktree).
- Quotas 2026-11-21: Codex 5h 0.04 / weekly 0.22 (resets 11-24 07:32 PST); Fable weekly 0.08 (resets 11-26 21:59Z);
  Claude weekly 0.15. Warn the operator at 0.80.
- Travel bundle: m2-air enrolled 2026-11-21 via add-recipient + `FORCE=1` publish on the M5 (recipients m4-air, m2-air);
  `password-bundle-show` PASS on m2-air; on m4-air it failed `security` rc 36 over SSH (locked Keychain or item ACL),
  operator to unlock and retry. Rev 2 E5 stays pending (needs `add-laptop` after a hub-deploy).
- Stale branches cleaned (restore bundle `~/.local/share/k3d-manager/branch-archive-2026-11-21.bundle`, 64 refs).

**Waiting on the operator:**
- Intent approval (E1-E3) for `docs/bugs/2026-11-21-password-bundle-keychain-and-input-errors-give-no-next-step.md`
  (P3, fix in v1.45.0 per operator; only `password_bundle.sh` + bats; fits WIP as 3rd). Then dispatch to Codex.
- Intent approval for `docs/plans/v1.45.0-red-team-gate.md` (runs after 2c, 2b, web-console C land).
- `make hub-sync` after the rev 2 land was refused by the permission classifier: operator runs it or allows it.
- m4-air `make password-bundle-show` result after `security unlock-keychain`.

**Next, in order (each task: spec → worktree → command → verify checklist):**

1. **web-console C (TOTP gate) — verify and land.**
   - Spec: `docs/plans/v1.45.0-web-console-c-totp-gate.md`. Worktree:
     `/Users/cliang/.local/share/k3d-manager/worktrees/v1.45.0/web-console-c-totp-gate` (base `01393a7b`).
   - State: agy Flash exited 0, nothing committed. Diff = 3 modified (`Makefile`, `not-installed.list`,
     `web_console_common.sh`) + 8 new (`bin/k3dm-web-console-totp`, howto, totp plist tmpl, gate/totpctl/totpd `.py`,
     `test_web_console_totp.py`, `web_console_totp.bats`). Worker claims pytest 2490 passed, shellcheck clean: unverified.
   - Checklist: diff vs spec Files and every Acceptance id (expect test gaps: only 14 pytest + 7 bats); run both suites +
     shellcheck + `git diff --check` + `_agent_audit`; each must_not red on base `01393a7b` (mutants); if gaps, send a
     correction resume, else Claude commits on the task branch; independent Sonnet verifier from Acceptance only; then
     `bin/k3dm-codex-dispatch land --slug web-console-c-totp-gate --test '<suites>'`; push; record VERIFIED.
2. **2c root daemon — finish, rebase, verify, land.**
   - Spec: `docs/plans/v1.45.0-remote-promote-2c-root-daemon.md`. Worktree:
     `/Users/cliang/.local/share/k3d-manager/worktrees/v1.45.0/remote-promote-2c-root-daemon` at wip `419b34c1` (clean).
   - Correction resume 8 items to check in `419b34c1`: ACL `ls -lde` checks, sudo priming, status rc, ditto `--noacl`,
     interactive bootout (prompt: `/Users/cliang/.local/share/k3d-manager/worktrees/v1.45.0/remote-promote-2c-root-daemon.run/pending-resume-8.md`). Missing items → resume Codex on
     `gpt-6.2-astra` (Codex weekly 0.22, fine).
   - Then rebase onto the release head (Makefile overlap with rev 2 `39a24a59`); earlier review: Sonnet M1-M22 PASS, N2/N6
     PARTIAL; Fable S1-S5 should-fix. Same checklist as item 1; land; record.
3. **Password-bundle Keychain P3 — dispatch on intent approval.**
   - Spec: `docs/bugs/2026-11-21-password-bundle-keychain-and-input-errors-give-no-next-step.md` (Files: plugin, its bats,
     howto, CHANGELOG; no overlap with 2c or C). Ask the operator to approve E1-E3 intents, write `**Intent approved:**`,
     push, then `bin/k3dm-codex-dispatch start --spec <that doc> --agent codex`. Verify: mutants listed in E1; N1
     password absent from stub argv log.
4. **Then:** 2b (`docs/plans/v1.45.0-remote-promote-2b-promote-wiring.md`) and web-console B
   (`docs/plans/v1.45.0-web-console-b-captures.md`) after 2c lands (shared Makefile; WIP ≤ 3, one dispatch per file); then
   red-team gate (`docs/plans/v1.45.0-red-team-gate.md`, intents pending, quota gate inside); then the release PR
   (Copilot capped until 12-01, so Argon reviews it).
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
