## Update — 2026-11-22 ~19:30 PST — 2b LANDED e3eb53ca (code bb5b6aa9); CI pending on head
- 2026-11-23: **hoverfocus v0.0.1 shipped** — PR #1 merged `d426f18` 14:09Z, enforce_admins re-enabled, tag v0.0.1 + GitHub release. v0.0.2 batches planned `docs/plans/hoverfocus-v0.0.2-bug-batches.md` (L1 Luna AppDelegate, F1 Flash Makefile/install, P1 live probe w/ operator ~15:30, L2 Luna Controller after P1); not dispatched, awaiting intent approval. Operator at work until ~15:30.
- 2026-11-23: hoverfocus PR #1 Argon review done (exit 0, read-only): 3 confirmed low/medium (reload fails open, AX element cache leak, Makefile sed escaping) carry → v0.0.2, 2 speculative; `docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md`. iTerm focus-follows-mouse coexists with HoverFocus (operator test). Next: CI on a4d9abb, operator merge, tag v0.0.1.
- 2026-11-23: hoverfocus PR #1 opened (m1-base → main, head a4d9abb, not draft); blind Argon review spec `docs/plans/review-hoverfocus-pr1-v0.0.1.md` dispatched (agy, role review).
- **2026-11-23 hoverfocus ship decision (operator):** ship v0.0.1 with E-L1 as is; 3 hoverfocus bugs (same-app switch, terminal cursor, install/TCC gaps) carry → v0.0.2. README limitations updated on m1-base `a4d9abb`; M1 PR next.
- **2026-11-23 hoverfocus E-L1 complete:** steps 1-2 pass; step 3 FAIL as spec-known limitation (same-app window switch has no effect) — filed P2-proposed `docs/bugs/2026-11-23-hoverfocus-same-app-window-switch-no-effect.md`; unfocused-cursor P3 also seen on Terminal.app. Operator decides whether same-app blocks M1 PR / v0.0.1.
- **2026-11-23 hoverfocus E-L1 (m2):** step 1 PASS (TextEdit behind iTerm, focus without raise), step 2 PASS (menu Running after `tccutil reset` + regrant + kickstart); step 3 (two TextEdit windows) pending. Filed P3 `docs/bugs/2026-11-23-hoverfocus-iterm-hollow-cursor-after-no-raise-focus.md`.
- **2026-11-23 dr-drill V4 root cause:** restored LDAP rejects drill `openldap-admin` password (bind rc=49, 12 DNs restored); `_err` in `hub_data_verify_ldap` exits drill before report. Filed `docs/bugs/2026-11-23-dr-drill-v4-ldap-admin-bind-err-exits-drill.md` (P2 proposed). Kept `dr-drill` cluster still up on m2.

- 2b landed on k3d-manager-v1.45.0: c1def92c (Luna tree, Claude-committed), 44b37351 (E7 HEAD cmp removed), bb5b6aa9 (appsets source only on pinned path), e3eb53ca plan LANDED. Overrides: --allow-instruction-files (copilot-instructions), --allow-out-of-scope (3 E7 fixtures), both operator-approved and on the spec.
- Next: CI green on e3eb53ca, then operator runs make hub-deploy REF=e3eb53ca (tmux), then live check. Did NOT run make hub-sync (outward-facing; hub reads deploy/hub).
- Raw web-console B captures moved to ~/.local/share/k3d-manager/captures/2026-11-22-web-console-b-raw/ (24) and 2026-11-22-root-scratch/ (3); write-up still owed.
- Open: P3 docs/bugs/2026-11-22-hub-promote-tty-driver-10s-deadline-fails-under-load.md (triage). M1b landed (bef450c). M1a LANDED m1-base 4cbd377; awaiting operator OK for m2 install + E-L1. Operator 2026-11-22: tag hoverfocus v0.0.1 initial release with the M1 PR.

## Update — 2026-11-22 ~15:20 PST — order PR #109 ready to merge; 2b resume 6 running

- Order PR #109 (`227bbdbe`): Claude E1/E2 pass with red controls, blind Argon no findings, CI green (publish skipped on the PR). Operator merged 2026-11-22 23:07Z (`428e60de`); bug LANDED; E3 owed after the 01:00 PT scan (dispatch run on main, build-push success, promote commit, no FAILED line).
- 2b resume 5: 120/124. Rulings: 120 = script gap (`stop` must pass 75 at run-lock, promote, read-deploy-hub, read-promoted-ref per Behaviour 7); 116 test snapshot; 118 fixture needs `+` refspec; 34 G regression broken by the new guards. Resume 6 (correction) running, watcher armed.

## Update — 2026-11-22 ~15:30 PST — order CI fix dispatched; 2b resume 5 running

- Order CI (`docs/bugs/2026-11-22-order-ci-missing-workflow-dispatch.md`): operator chose "Fix now", route
  "Spec + Luna" (shopping-cart rule: no direct Claude edits). Fable spec review: needs changes, 5 should-fix + 2 nits,
  all applied (`7cf17dce`). Intents approved by operator. Base branch `fix/cve-manual-rebuild` created on order origin
  at `00c9fcd` (dispatcher refuses `--branch main`). Luna dispatched, slug `order-ci-workflow-dispatch`. Next: verify
  E1/E2 in the worktree, push, normal PR, blind Argon review, operator merges, Claude checks E3. Do not `land` into
  the order checkout (it is on `fix/automerge-app-token`).
- 2b: Claude's independent run of resume 4 = `hub_promote.bats` 71/71, shellcheck 0. Resume 5 (E4, sudo/launchctl
  guards, table) running; watcher armed.
- Restart-webhook transient-error P3 filed (`d576c5c9`). E6 sampler still running to ~15:41.

## Handoff — 2026-11-22 14:47 PST — promoted aa920a6f; Hostinger LIVE-VERIFIED; E6 sampling — START HERE

**Objective:** finish v1.45.0 (2b land, B captures, red-team gate, release PR); groom 2026-11-22 (Step 0 triage + ideas).

**Open dispatches 1 of 3 (all Luna, started 2026-11-22):**
- `remote-promote-2b-promote-wiring`: land may use `--allow-instruction-files` for `.github/copilot-instructions.md` only (`f12bcc16`).
- correlator P3 LANDED `f99f59f4`, VERIFIED (119 green; pre-fix 4 red; 2 mutants red); E2 live owed after hub runs it.
- `2026-11-09-hermes-reauth-lasts-24h-and-is-reusable` (slack-relay index.js; E2 intent approved `ea602bdc`).
- reauth P3 LANDED `e1972118`, VERIFIED (54 green; pre-fix 4 red; M4 mutant red after resume 2); E2 live after
  `make deploy-worker`. E2 wording changed to '10-minute' (operator 2026-11-22).
- 2b: resume 2 still incomplete (E5 4 tests + E7 2 done; E1 and E2 one test each; E3, E4, guards, table missing).
  It found and fixed a Makefile `$_got` escaping defect (M10). Resume 3 = E1+E3 only in hub_promote.bats; resume 4
  planned = E4 + sudo/launchctl guards + base/mutant table. Review the Makefile change at verify.
- Hostinger-status P3: verified offline, committed `fe64b3f7` on task branch (55 node / 10 bats / 46 pytest green;
  pre-fix 1+5+2 red; N2 mutant red). LANDED `8f6de4c1` (operator approved `--allow-out-of-scope` for
  webhook_make_targets.py), VERIFIED. Live: Slack entry removed + /cluster-status hostinger
  HEALTHY 21/0/0 (operator 2026-11-22); owed: `make deploy-worker`, then `/k3dm help`.
- 2b resume 4 running (correction): M8 misplaced `--approval` → exit 2 fix + 2 fixture fixes; resume 3 found it.
- On each exit: verify from git (not the worker's report), must_not red on old code, full land `--test` set under
  sandbox-exec (exclude machine_setup test 187: `tty_limited` `ps` denied, P3 `eef73df5`), push, then land; never commit
  on the release branch while a land runs (ff-only merge).

**Grooming 2026-11-22 (DONE, see docs/grooming/2026-11-22.md):**
- Argon classified the 53 unclassified OPEN bugs (committed `7ababe12`; 3a/3b drafts `2b15ede0`); 10
  Argon P3→P2; Claude would accept 3 (promote-waiting false alert, Hermes r7 first ESO group, ACG ssh config).
- 109 OPEN bugs: 8 P2, 101 P3; 36 P3 on second pass (close candidates); 15 carry a stale `carry → v1.44.0`.
- Fable blind ideas review done (ranks: weekly live-check session 1, verifier-first 2, stall watch for Claude jobs 3,
  promote CVE pin sync 4, ACG login 5, dev-hub gate 6; drops: sprint dashboard, CVE research, web console, /clear graph,
  WIP>3 row; v1.46.0: move out bounded-index + bug-lifecycle-metrics).
- Drafts (untracked, not reviewed): `docs/plans/remote-promote-3a-cloud-request-card.md` (Q1 early policy
  check location blocks dispatch) and `...-3b-relay-totp-signed-approval.md` (11 open questions; key hex-decode,
  id regex keeps `d`, skew window). Operator: draft now, implement on the release timeline.
- v1.46.0 is 7/5 before 3a/3b; needs swaps, operator decides.
- Carried agenda items (from 11-21): pre-commit `**Fix commit:**` rule; agy-quota-dashboard DRAFT placement; offline
  test-all P2 close C3/C4; pull `v1.51.0-bug-count-query-translation` forward with the ask-docs P2; out-of-band repo
  tracking (dirused) + per-project quota.

**Tonight (operator home):** PROMOTED 14:40: deploy/hub 4217648..aa920a6 (appsets ok, platform-ops ok); relay Worker version
  d6a3ac28. Bundle E6 sampling 1 h (14:41 first sample: PID '-', exit 0, success=1, last publish 14:27). Hostinger-status
  LIVE-VERIFIED (after `make restart-webhook`; new P2 filed: hub-deploy never restarts webhook on code change).
  Reauth E2: 10-minute reply confirmed; second-card reauth owed at next real incident.
  istio-ambient stale sandbox appset: P3, carry → v1.46.0 (operator). v1.46.0: bounded-index + bug-lifecycle-metrics moved
  to ordered backlog 10/11 (operator, grooming); v1.46.0 now 5 plans; 3a/3b need a swap to enter.

**v1.45.0 state:** remote-promote 1/2a/2c/2d/2e landed, 2b running; travel bundle, multi-project, stall-recovery landed;
web-console A live-verified, C LANDED `1026dbe2`/`c79c8ec0`, B = operator captures; make-up-app-none carried out.

**Waiting on the operator (home ~2 h from 2026-11-22 evening):**
- `make hub-sync` + `make hub-deploy REF=<release head>`, then Claude read-only checks (C, 2c, travel rev 2, bundle timeout E6).
- Slack relay Worker deploy + Hermes E2 checks after those fixes land; web-console B captures.
- Live checks owed: 2d E11; travel bundle E3/E5; test-all E3; stall C E8, B E9/E10; dirused M9b E2 (Mon 11-23, office).

**Standing facts:**
- Handoff guard: `.claude/hooks/handoff-on-clear.sh` reports STALE if commits land after this header; bump the time on edit.
- Older handoffs and logs, verbatim: `memory-bank/archive/activeContext-2026-11-22.md` (then `-2026-11-21.md`).
- Source of truth for open work: `docs/bugs/` Waiting-on lines, `bin/k3dm-codex-dispatch open`, plan Status lines.
- Known agent failure modes: Codex sandbox cannot commit; agents report suites they did not run; worker cd failures can
  delete untracked files in the main checkout (`git status` after each verifier run); mutants can reach real sudo
  unless the suite stubs sudo/launchctl in setup.
- Carried small items: ask-bash linked-worktree P3 unfiled; revoke the zshenv GitHub token; SHA-256 pin nit in
  agent_dispatch_dashboard.bats test 54; locked-Keychain WARNs in hub-deploy; M2 `~/.ssh/config` is a copy (ask first).

