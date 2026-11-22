# Progress — v1.45.0 (older entries: `memory-bank/archive/progress-2026-11-21.md`, then `progress-2026-11-20.md`; open work lives in `docs/bugs/` Waiting-on lines and the dispatch ledger)

## v1.45.0 status (compressed 2026-11-21; detail in the archive)

- **LIVE-VERIFIED:** remote-promote Part 1 (E9); 2e CVE-pin branch writer (cutover live, E9 PASS); web-console part A
  (E11-E14 on m5-air); priv_open fix (E4 on m4-air); plan-quotas-beside-fable (E2); codex-row float-up (E2, `83344176`);
  dispatch-stall A and D; m5 PATH bug (zshdotfiles#4/#5).
- **LANDED / VERIFIED, live owed:** travel bundle `ddd9329e` (E3) and rev 2 `39a24a59` (E5, needs hub-deploy);
  test-all metrics `64a8de5c` (E3); dispatch-stall C `e05a08ed` (E8) and B (E9/E10); remote-promote 2a VERIFIED, 2d (E11);
  hub-deploy self-update `3b541f3b`; remote-promote 2c `c17eae59` (VERIFIED offline, hub-deploy owed); password-bundle
  Keychain P3 `3971fa3f` (m4-air retry owed); multi-project M2 bug metrics; Astra metrics; lib-foundation v0.5.7 subtree.
- **Open dispatches:** web-console C r2 (Luna resume 7 done; 168-mutant rerun running before land); agy-repo-mode P3 LANDED `1e237612` (244/244; mutants all red after resume 2 added WAL/size/cache-allowlist tests); live E6-E8 owed after hub-deploy.
- **Not started:** 2b promote wiring, web-console B (both unblocked by 2c), red-team gate (intents approved).
- **Rechecked 2026-11-21:** offline test-all P2, C1-C4 none reproduce (`af2cc5d9`), to grooming.
- **Captured P3:** hub_deploy.bats catch-up test index.lock race (`0c999bbe`).
- **v1.46.0:** plan 6 travel-bundle iPad SSH spec v1.1, intent approved (implementation in v1.46.0 only).

## Log

- 2026-11-21: autoCompactWindow 400000 trial for the 1M window (`1ab308ef`, operator approved); void if Observed compaction point stays near 167K. CLAUDE.md/rules.md 200K wording corrected.

- 2026-11-21: agy repo/mode P3 landed `1e237612` (Flash 3 runs; Claude mutation check 16/16 red; audit marker for 17 unknown->print assert rewrites).

- 2026-11-21: five bug statuses corrected + Fix commit headers (`b8f1b19b`); Fix-commit recurrence on 2026-10-25 doc (`a985b682`, operator decision); Linux CI red fixed: password-bundle M6/N6/N7 assumed a Mac host (`4b8561af`, P3 doc, CI pending).

- 2026-11-21: P3 agy transcript sessions always unknown repo/mode — filed, dispatched to Flash (`gemini-3.8-flash-medium`).

- 2026-11-21: progress compressed; full log archived to `memory-bank/archive/progress-2026-11-21.md`.
