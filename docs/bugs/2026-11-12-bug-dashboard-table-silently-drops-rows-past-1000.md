# Bugs dashboard table silently drops every bug past row 1000

**Status:** OPEN — captured 2026-11-12
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-12
**Introduced by:** pre-existing (the 1000-row cap in `bin/k3dm-vectordb-metrics`)
**Should have been caught by:** none
**Prior art:** none above threshold (find-similar-docs unavailable: vector store context missing; exact-slug glob empty)
**Approval:** none yet (capture only)

`publish_bug_metrics` sorts the bug rows and pushes only `rows[:1000]` as `k3dm_bug_info`
(`bin/k3dm-vectordb-metrics:750-756`). It sets `k3dm_bug_info_truncated{repo}` (`:811`), but
`grafana-dashboard-bugs.yaml` never reads it, so the per-bug table gives no sign that rows are missing.

**Evidence (2026-11-12, M5 Pushgateway, push from `origin/k3d-manager-v1.43.15`):** 1107 docs in
`docs/bugs/`, exactly 1000 `k3dm_bug_info` rows for k3d-manager. The 107 missing are the oldest
releases: 93 CLOSED, 13 fixed/landed, 1 DEFERRED. No open bug was hidden. Aggregate counts
(`k3dm_bug_status_docs`) are computed over all rows and are correct.

Why it matters later: rows sort newest release first, so an open bug filed against an old release
would be the first to drop off the table once the count grows (about 15 new docs a day this week).
