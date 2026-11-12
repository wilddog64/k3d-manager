# Agent Cost context panel: "observed" is a stale outlier and "configured" shows the window, not the trigger

**Status:** OPEN — found 2026-11-11 by the operator ("seems to be odd and not make sense"); root-caused by Claude from the transcripts
**Priority:** P3
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (The Agent Cost context panel's ceiling and threshold metrics are degraded and misleading across the Oct 16 settings change, but auto-compaction works normally (~167K daily max) and operators can work around it by narr…); Claude proposed P3. Higher stands until the operator decides.
**Triage:** passed over, 1st (out of v1.44.0 at the 10-P3 cap) — grooming 2026-11-12, operator. Priority: operator kept Claude's P3 over Argon's P2.
**Waiting on:** operator decision — since 2026-11-12
**Introduced by:** `82c1d9c8` (v1.43.14, context ceiling, floor and configured threshold)
**Should have been caught by:** spec
**Prior art:** `docs/bugs/2026-11-11-claude-context-floor-and-ceiling-count-only-turns-since-last-export.md` — read, different root cause (that fix made the ceiling see all turns, which exposed this one)
**Approval:** operator, 2026-11-11 ("file a P3 bug")

## Symptom

Agent Cost "Floor, observed ceiling and configured threshold" reads floor 90.1K, observed 389K, configured 200K
(operator screenshot, 2026-11-11). Observed is about twice configured.

## Root cause

- **observed** is `max` of main-session turn context over the window (`bin/k3dm-dispatch-metrics:2317`). The 389K is
  one session on 2026-10-16 (388,911 tokens). Daily maxima from local transcripts (2026-11-11): Oct 9–16 had 1,732
  turns above 200K; from Oct 17 none, with a daily max of 164–188K. A max over a window that spans a settings change
  shows the old regime until the window passes it (around 2026-11-15 for 30d).
- **configured** is `k3dm_claude_auto_compact_tokens` (`:2359`), the 200K context window setting. Compaction
  fires at about 167K (window minus a reserve), which is where every daily max since Oct 17 sits.
- **floor** (median first turn after compaction) is sound.

## Fix direction

Show observed as p99 or as the max since the latest settings row, and show configured as the effective trigger
(about 167K) or relabel it "window". Panel in `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`.
