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
