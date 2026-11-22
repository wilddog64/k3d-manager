# Progress — v1.45.0 (older entries: `memory-bank/archive/progress-2026-11-22.md`, then `-2026-11-21.md`, `-2026-11-20.md`; open work lives in `docs/bugs/` Waiting-on lines and the dispatch ledger)

## v1.45.0 status (compressed 2026-11-22)

- **LIVE-VERIFIED:** remote-promote Part 1 (E9); 2e CVE-pin branch writer (E9); web-console part A (E11-E14);
  priv_open fix (E4); plan-quotas-beside-fable (E2); codex-row float-up (E2); dispatch-stall A and D; m5 PATH bug;
  land instruction-check P2 (E2, by the C r2 land, `ffc6f3ed`).
- **LANDED / VERIFIED, live owed:** travel bundle `ddd9329e` (E3), rev 2 `39a24a59` (E5); password-bundle Keychain P3
  `3971fa3f`; password-bundle timeout P2 `e3f2bcaf` (E6); test-all metrics `64a8de5c` (E3); dispatch-stall C (E8), B
  (E9/E10); remote-promote 2a, 2c `c17eae59`, 2d (E11); hub-deploy self-update `3b541f3b`; multi-project; agy repo/mode
  P3 `1e237612` (E6-E8); web-console C `1026dbe2`/`c79c8ec0` (live after hub-deploy). All need a hub-deploy first.
- **Running (Luna):** 2b promote wiring (resume 2). Correlator P3 `f99f59f4` and reauth P3 `e1972118` landed (E2 intent approved).
- **Not started:** web-console B (operator captures), red-team gate (intents approved, after 2b and B), release PR
  (Argon review; Copilot capped until 12-01).
- **Carried out of v1.45.0:** make-up-app-none (`93fe6b62`), to this grooming.
- **app-cve-scan auth fixed 2026-11-22:** classic PAT `k3dm-app-cve-scan` (repo, read:packages), expires 2027-02-20.
- **v1.46.0:** 7/5 (iPad SSH plan 6 intent approved; Tailscale plan 7 scope revision owed); 3a/3b drafts want in.

## Log

- 2026-11-22: 2b resume 2 incomplete (E1-E4 thin, guards/table missing); resume 3 narrowed to E1+E3.
- 2026-11-22: Hostinger-status slash-command retirement P3 dispatched to Luna (2 of 3 open).
- 2026-11-22: Hermes reauth P3 LANDED `e1972118`, VERIFIED offline (resume 2 fixed M4 test gap); E2 after deploy-worker.
- 2026-11-22: Hermes correlator P3 LANDED `f99f59f4`, VERIFIED offline; Classified lines `7ababe12`, 3a/3b drafts `2b15ede0`.
- 2026-11-22: reauth worker exited 0, verify found M4 test gap + out-of-scope intent edit, resumed (correction); 2b exited 0 incomplete (tests missing), resumed (continue).
- 2026-11-22: memory-bank compressed (operator ask); full log archived to `memory-bank/archive/progress-2026-11-22.md`.
- 2026-11-22: grooming started: Argon classified 53 bugs; Fable ideas review done; remote-promote 3a/3b drafted (untracked).
- 2026-11-22: 2b, Hermes correlator, Hermes reauth dispatched to Luna (3 of 3).
