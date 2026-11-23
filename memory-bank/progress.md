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

- 2026-11-22: order PR #109 open, verified, Argon no findings, CI green — operator merge owed. 2b resume 6 (4 reds) running.

- 2026-11-22: order CI spec Fable-reviewed and approved; Luna dispatched (`order-ci-workflow-dispatch`); 2b resume 4 verified 71/71, resume 5 running; restart-webhook P3 captured.

- 2026-11-22: promoted aa920a6f + relay d6a3ac28; Hostinger-status LIVE-VERIFIED; reauth E2 partial; P2 filed hub-deploy-leaves-webhook-on-stale-code.
- 2026-11-22: v1.46.0 cut to 5 (bounded-index, bug-lifecycle-metrics → backlog, operator); istio-ambient P3 → v1.46.0; CI green aa920a6f.
- 2026-11-22: CI reds fixed `aa920a6f`; kagent idea; P2 filed: istio-ambient ApplicationSet targets retired ubuntu-k3s, Hostinger Istio unmanaged by Argo.
- 2026-11-22: Hostinger E2 partial live: Slack entry removed, /cluster-status hostinger HEALTHY 21/0/0; deploy-worker + /k3dm help owed.
- 2026-11-22: Hostinger P3 LANDED `8f6de4c1`, VERIFIED (operator scope go); reauth-reply E2 wording → 10-minute (operator).
- 2026-11-22: Hostinger P3 verified offline (`fe64b3f7` task branch); land refused out-of-scope test file, operator go asked. 2b resume 4 (M8 fix) running.
- 2026-11-22: 2b resume 2 incomplete (E1-E4 thin, guards/table missing); resume 3 narrowed to E1+E3.
- 2026-11-22: Hostinger-status slash-command retirement P3 dispatched to Luna (2 of 3 open).
- 2026-11-22: Hermes reauth P3 LANDED `e1972118`, VERIFIED offline (resume 2 fixed M4 test gap); E2 after deploy-worker.
- 2026-11-22: Hermes correlator P3 LANDED `f99f59f4`, VERIFIED offline; Classified lines `7ababe12`, 3a/3b drafts `2b15ede0`.
- 2026-11-22: reauth worker exited 0, verify found M4 test gap + out-of-scope intent edit, resumed (correction); 2b exited 0 incomplete (tests missing), resumed (continue).
- 2026-11-22: memory-bank compressed (operator ask); full log archived to `memory-bank/archive/progress-2026-11-22.md`.
- 2026-11-22: grooming started: Argon classified 53 bugs; Fable ideas review done; remote-promote 3a/3b drafted (untracked).
- 2026-11-22: 2b, Hermes correlator, Hermes reauth dispatched to Luna (3 of 3).
- Order main CI after #109 merge green (run 45081470809, promote e64ae03b); E3 still waits for the 01:00 PT scan.
- hoverfocus (new OOB repo, focus-follows-mouse without raise): M1 specs a5e315b8 (umbrella, M1a Luna core, M1b Flash shell, parallel split trial); Fable review running; repo name/visibility and intents pending operator.
- web-console C VERIFIED offline (E1-E9 PASS at 3fad525c, ladder offline_tested marked); E10-E11 live owed with part B. password-bundle hang bug LIVE-VERIFIED (E6). 2b resume 7 running: exit-75 allow-list made path-dependent per Part 1 B14 (resume-6 instruction lacked the approval-path qualifier).
