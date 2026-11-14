# Bug: plan dashboard lags a pushed Status change by up to about 20 minutes

**Status:** OPEN — captured 2026-11-14 by Claude
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-14
**Introduced by:** unknown
**Should have been caught by:** none
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unreachable from the M4); idea row 2026-11-14 in `docs/ideas.md` (dashboard tracks the dispatch ledger) is the related, different gap
**Approval:** none yet (capture only)

## Symptom

Operator: "some of the information seems to be stale for longer than 5 mins". Measured on the hub (read-only, 2026-11-14) for commit `1530a115` (plan 1 Status to IN PROGRESS):

| Stage | Cadence | This change |
|---|---|---|
| push to GitHub | — | 19:53:23Z |
| repo-sync fetch on the M5 | launchd 300 s | 19:54:22Z (59 s) |
| Hermes cycle publishes `k3dm-plan-docs` (end of cycle, `bin/k3dm-hermes:1033`) | launchd 300 s, observed start-to-start about 7 min (19:15, 19:22, 19:29, 19:36, 19:43, 19:50) | last push 19:51:36Z, before the fetch; 19:55:43Z still `execution="proposed"` |
| Prometheus scrape of the Pushgateway (`localhost:19094`) | scrape interval | not measured |
| Grafana bugs dashboard auto-refresh | `"refresh": "5m"` (`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`) | — |

Worst case is about 5 + 7 + 1 + 5 = 18-20 minutes from push to screen; a doc change waits for a fetch, then for the next full Hermes cycle, then for the dashboard refresh.

## Fix direction (for triage)

Publish plan and bug doc metrics when repo-sync moves the release-branch ref (event-driven, about one minute after a push) instead of only at the end of the Hermes cycle; set this dashboard's refresh to 1m. Why launchd starts Hermes about every 7 min rather than every 5 is not known (cycles complete in about 1.3 min, e.g. 19:50:57 to 19:52:15Z).
