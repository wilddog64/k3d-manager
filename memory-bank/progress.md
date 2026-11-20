# Progress — v1.45.0 (older entries: `memory-bank/archive/progress-2026-11-20.md`, then `progress-2026-11-17.md`; open work lives in `docs/bugs/` Waiting-on lines and the dispatch ledger)

## v1.45.0 landed so far (compressed 2026-11-20; detail in the archive)

- lib-foundation v0.5.7 (exclusive lock claims) released and subtree-pulled `8fad0831`; run_parallel P2 VERIFIED.
- Travel bundle `ddd9329e`/`d14b5d9e` and test-all metrics `64a8de5c` LANDED (live checks owed).
- Multi-project M2 bug metrics `467e1de0` LANDED; Astra metrics `34502bfe` LANDED.
- Dispatch-stall: A LIVE-VERIFIED, D LIVE-VERIFIED, C LANDED `e05a08ed` (E8 live owed), B VERIFIED `4c1a7b4c`+`c0c0dbfe` (E9/E10 live owed).
- Remote-promote: Part 1 `643747e5` (E9 LIVE-VERIFIED), 2a VERIFIED `e826f6f8`, 2d in correction (be8bff34 + test gaps).
- Web-console part A LANDED `6b34bd55`+`8faebd87`, verify recorded PASS (live E11–E14 owed).
- Dashboard: plan child-spec fold `d1bc155f`, Earliest/Latest valueSize `fd9bc6a4`, Releases / 7 days tile `7dfa6738` (live after next promote).
- Hub-deploy self-update `3b541f3b` VERIFIED (live E2 after next promote). Hermes gh-token regenerated 2026-11-19 (exp 2027-02-18).

## Log

- 2026-11-20 04:30 PST: CI green on 5beb4cc9 (7/7 check-runs). 2d resumed (resume 3, pid 95533) after Codex reset.
- 2026-11-20: child B (dispatch-stall-b-approval) dispatched to Luna (operator "go ahead"), pid 23166. WIP 2/3 (2d, child B). Next queue: part C, then 2e. Promote after 2d lands.
- 2026-11-20: Release forecast row: added "Releases / 7 days" stat (panel id 34, x20 y11 4x4; count of k3dm_release_shipped_timestamp_seconds within 7d, area sparkline). Operator exception ("go ahead"), Claude direct, no dispatch. bats 49/49 (new test red on old dashboard), dashboard pytest 152, appsets 51. Visible after next promote. Child B worker exited 05:14 (uncommitted changes), verifying.
- 2026-11-20: child B verifier (Sonnet) PASS on 6854c325: 14/18 mutants killed; gaps sent back to Luna as correction 1 (resume 2, pid 91518): landed/violation refusal test, save-before-resume ordering (M8/N4), webhook URL scrub (N5), hermes.md list split. 2d still running.
- 2026-11-20 05:45: child B dispatch-stall-b-approval LANDED 4c1a7b4c + c0c0dbfe, VERIFIED (Sonnet PASS; gaps closed in correction; Claude re-mutated 3 guards, each red). Claude correction error (clean exit refused) caught by Luna vs M5. Live E9/E10 pending: needs make deploy-worker (relay, operator terminal), M4 Keychain copies of k3dm-hermes-approval-drain-token + k3dm-slack-webhook (make machine-setup ROLE=worker FROM=m5-air.local), stall watcher K3DM_STALL_DRAIN_CMD, toy dispatch, /hermes-auth within 24h. WIP 1/3 (2d). Velocity tile 7dfa6738 pushed.
- 2026-11-20 05:55: 2d exited rc 0 (85 tests, ruff 0.15.8 clean via scratch venv); Claude committed be8bff34 in worktree; Sonnet Acceptance verifier running. Operator running machine-setup ROLE=worker FROM=m5-air.local on M4 (child B E9/E10 prep).
- 2026-11-20 06:05: operator ran machine-setup ROLE=worker on M4: drain token + slack webhook ok (already present, not re-exported); Error 1 from gemini-cli-api-key (operator-supplied, by design) and antigravity-cli cask vs unowned agy 1.5.13 -> captured P3 docs/bugs/2026-11-20-machine-setup-antigravity-cli-refuses-unowned-agy.md.
- 2026-11-20 06:25: relay deployed by operator from M4 (version f02af9db); no webhook/hermes restart needed (M5 hermes ignores d IDs). 2d Sonnet verifier: 54 mutants, 47 killed, 6 real gaps (M9 absent tag + ! flag, M10 already_spent note_refusal, M5 merge ancestor, M1 --no-tags, M13 min cap); Claude reproduced absent-tag survivor. 2d resume 4 (correction, tests only) running.
- 2026-11-20 (morning): memory-bank compressed (operator ask): activeContext 165K -> ~8K, progress 81K -> ~4K; verbatim copies in archive/*-2026-11-20.md. 2d correction 412e59be (91 tests); Claude reran 6 gap mutants, all killed.
- 2026-11-20 (morning): 2d LANDED b42cb927 + 2c6a4cc5, VERIFIED (verify recorded). WIP 0/3. Push then promote after CI green.
- Sonnet-verifier trial (report at grooming 2026-11-22): web-console A — agree PASS; Sonnet caught revoke mutant H surviving; Claude alone caught the missing `set -euo pipefail` and 13 inline comments. Child B — agree PASS; Sonnet caught 4 test gaps (landed/violation refusal, save-before-resume, webhook URL scrub, docs split); its counts were stale (49/421 vs Claude 51/429). 2d — Sonnet strict FAIL, 6 real gaps from 54 mutants, Claude reproduced the top one and agreed; Claude alone ran the pinned ruff lint the worker skipped.
- 2026-11-20 (morning): MEMORY.md 9063 -> 8662 bytes (3 pointers moved into hub_projects / hub_ref_observability, one line shortened; no pointer lost, no memory wrong or expired). Sonnet trial lines logged in progress.
- 2026-11-20 (morning): ideas row added (memory-bank size budget + /post-merge 7c recipe), operator ask.
- 2026-11-20 (morning): 3 ideas rows for grooming (rework_ratio + operator time, required reviewed field, weekly live-check slot), operator ask.
- 2026-11-20 (morning): CI lint red on 82d105e4 (6 pyflakes: 2 unused datetime imports in bin/k3dm-dispatch-recover from child B, 4 in test_promote_mover.py from Luna 412e59be). Claude miss: linted 2d before the correction and never ran pinned ruff on child B. Fixed (claude_edit after land); lint clean, 91 + 18 tests pass.
- 2026-11-20 (morning): "other" in Tokens by repo traced (6.45 M = one dispatch whose worktree version v1.44.0 differs from its ledger version v1.44.1); appended to the tokens-by-repo P3.
- 2026-11-20 06:49: CI green on 9d7973b6 (7/7). Promote SHA given to operator: 9d7973b62d04063c4af905da3909567fbcbaf596. Docs-only commits pushed after.
- 2026-11-20 07:23: promote 3d5fd9ef -> 9d7973b6 done by operator (tag hub-promote/20261120T152130Z; appsets-check ok, platform-ops ok, exporter rolled out). hub-deploy self-update E2 LIVE-VERIFIED from the pane. ArgoCD hub-grafana-dashboards still on 3d5fd9ef at 15:23Z (waiting on its poll) before checking the velocity tile.
- 2026-11-20 07:26: ArgoCD hub-grafana-dashboards synced 9d7973b6 on its own at 15:25:11Z (no refresh needed, ~3.5 min after promote). Velocity tile live: panel 34 Releases / 7 days, Prometheus count = 3 (v1.44.0, v1.44.1, v1.44.2); operator screenshot shows it.
- 2026-11-20 07:31: operator ran /hermes-auth 07:29 PST (24h). Handoff written; operator /clear next. Next session: child B E9/E10, child C E8 judgement, web-console A E11-E14.
- 2026-11-20 ~08:00: E9 toy staging hit the production root with the real Codex (smartcd `cd &&` skipped the export); stopped in ~15 s, abandoned; P3 docs/bugs/2026-11-20-toy-dispatch-staged-in-production-root-real-codex.md. Watcher does not call the drain yet (stall-recovery part 1).
- 2026-11-20 ~08:05: P1 filed: approvals drain blocked by Cloudflare UA (1010); blocks E9 and Hermes Slack approvals; spec ready, Flash dispatch pending intent approval.
- 2026-11-20 ~08:15: dirused M9a LIVE-VERIFIED (E2, operator); M9b spec next (outside k3d-manager releases).
- 2026-11-20 ~08:25: dirused list-local-time spec written (v0.0.24); intent approval pending; M9b waits on SEVERE proof.
- 2026-11-20 ~08:35: dirused list-local-time dispatched (Flash). WIP 2/3.
- 2026-11-20: P1 approvals UA LANDED 970aeb23 (Sonnet verifier all pass); E4 live passed on M4 (no-UA 403 1010 vs UA 200; fetch_approvals empty queue). Pending E5: E9 fresh toy card + promote 970aeb23 for M5 Hermes. dirused list-local-time LANDED aa41dc0 (169/169, verifier mutants a-g red; CHANGELOG moved under Unreleased), PR wilddog64/dirused#37, Argon blind review running.
- 2026-11-20: dirused PR #37 merged 2e62aed, tag v0.0.24 (CI green, Argon clean). Pending operator E2 on jump box. P1 E5 pending: E9 toy card + promote 9c3345ba after CI.
- 2026-11-20: E9b staged: toy e9b-approve (scratchpad/e9b root, stub codex) card posted d1-a4a50fac, health probe passed (health_alert_at 0). Waiting on operator Approve, then Claude drains by hand.
- 2026-11-20: child B E9 PASS (e9b-approve d1-a4a50fac: one resume, Slack confirm line, relay queue empty). P1 E5 part 1 done; part 2 = promote + M5 Hermes r approval. Next: E10 Deny on old e9-approve card.
- 2026-11-20: child B E10 PASS (Deny d1-9593afc1: no resume, proposal stays proposed per spec :120, relay empty). Child B LIVE-VERIFIED. Toys e9-approve, e9b-approve abandoned in scratch roots. Open: P1 E5 part 2 (promote 72ab5903+, M5 Hermes r approval); dirused E2 (operator).
- 2026-11-20: dirused v0.0.24 E2 partial (operator 08:50 PST): /update 0.0.23->0.0.24, list v2 header, # created= and lastWrite in Pacific (-08:00) confirmed; /fromlist m9a2.txt and old m9a.txt replays not yet shown. Spec docs/plans/dirused-list-human-sizes.md written (v0.0.25: list v3, minsize=1GB, size column beside exact bytes); intents pending operator approval.
- 2026-11-20: dirused-list-human-sizes dispatched to Flash (dirused branch list-human-sizes from 2e62aed, v0.0.25; spec e83867d0). WIP 1/3.
- 2026-11-20: dirused-list-human-sizes Flash exit 0, 4 files in scope; Claude review: logic matches spec (v3 header, FormatMinSize exact units, size col via Format.Short, reader v1/v2/v3, bytes authoritative); note Flash reflowed the one-line Read/Write bodies (diff noise, behaviour same). dotnet test 188/188. Sonnet verifier from Acceptance running.
- 2026-11-20: dirused-list-human-sizes LANDED dirused@67ce6ee (verifier: M1-M4,N1-N3 pass, 12 pre-fix red, mutants red), PR #38 open; Windows CI + Argon blind review running.
- 2026-11-20: PR #38 Windows CI red: tests/Dirused.Tests/ProgramPurgeTests.cs:292 asserted 6 columns (Windows-only suite, missed in spec Contract readers = spec defect, not Flash). Claude fixed 6->7 in dirused@f491e45, pushed; Argon blind review: no findings. CI rerunning.
- 2026-11-20: dirused PR #38 merged c91e9b7 (CI 4/4 green on f491e45, Argon no findings); tag v0.0.25 pushed; release build running. Next: operator E2 on jump box.
- 2026-11-20: dirused v0.0.25 released (win-x64/arm64 zips + .sha256). Waiting on operator E2 (jump box).
- 2026-11-20: dirused v0.0.25 E2 steps 1-3 PASS (operator 09:16 PST): update 0.0.24->0.0.25, m9a3.txt v3, minsize=1GB, size col 138G/9.8G/8.5G beside exact bytes, /fromlist m9a3.txt /purge same 3 rows+statuses, 0 skipped. Outstanding: /fromlist m9a2.txt /purge (v2 replay) for both v0.0.24 and v0.0.25 E2.
- 2026-11-20: dirused v0.0.24 and v0.0.25 LIVE-VERIFIED: /fromlist m9a2.txt (v2) on 0.0.25 reads, same 3 rows, 0 skipped; v3 E2 passed earlier. Both plans closed.
- 2026-11-20: dirused M9b spec rev 1 written (docs/plans/dirused-m9b-stop-delete-start.md, v0.0.26, Flash, risk medium); /spec-review checklist fixes applied; Fable + Astra blind reviews running; dispatch waits on proof 6 (SEVERE lines, operator findstr), review adjudication, intent approval.
- 2026-11-20: M9b spec rev 2: Fable + Astra blind reviews adjudicated (20 rows; 1056/STOP_PENDING, ProbeHeld hold-back, warning containment, ENUMERATE_DEPENDENTS fixed); operator dropped catalina/SEVERE check (stop+start by SCM state only), proof 6 dropped; waiting on intent approval then Flash dispatch.
- 2026-11-20: M9b intents approved (operator); spec committed 5209b6b6; dirused branch m9b-stop-delete-start pushed at c91e9b7; dispatched to Flash (slug dirused-m9b-stop-delete-start). WIP: 1 open dispatch.
- 2026-11-20: CI 7/7 green on 5209b6b6 (272e4f64 run had test(2) cancelled by the push); operator asked to run make hub-deploy REF=5209b6b6 for P1 E5 part 2.
- 2026-11-20: P1 hermes approvals UA bug LIVE-VERIFIED (E5 part 2 on M5 after hub-deploy 5209b6b6: http 200 ua k3dm-hermes/1). Release PR no longer blocked by this P1.
