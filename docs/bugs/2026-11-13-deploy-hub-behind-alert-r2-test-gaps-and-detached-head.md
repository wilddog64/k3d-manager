# deploy/hub behind alert: three test gaps, and a detached hub root publishes stale counts as fresh

**Status:** OPEN — captured 2026-11-13 from the round-2 cross-model review of plan 3 (Claude)
**Priority:** P3 (proposed: test gaps plus a stale-count edge on a detached hub checkout; the normal path behaves correctly)
**Classified:** pending second-agent classification
**Introduced by:** plan 3 `deploy-hub-behind-alert` (round 2 correction)
**Should have been caught by:** offline test (items 1–2); spec (item 3: the round-2 brief named only `fetch_failed` as "did not fetch")
**Prior art:** exact-slug glob, none; `make find-similar-docs` not run
**Waiting on:** operator decision

## Symptom

From the round-2 review (Fable, 2026-11-13). Each item was shown in a scratch copy by a mutant or an ad hoc scenario:

1. Test gap: the `K3dmPromoteWaiting` mutant `expr: k3dm_repo_sync_promotable >= 0` passes promtool, because no input series ever
   holds 0 (`scripts/tests/bin/test_dashboard_queries.py` ~306-311). Only a string assert on the expr catches it. The producer never
   emits 0, so there is no effect today.
2. Test gap: two new paths in `bin/k3dm-repo-sync` have no test. Removing the previous-state upstream-branch fallback (~451-454)
   or the carry-forward call in the `except Exception` handler (~477-480) leaves all 12 promote-backlog tests green.
3. With the hub root on a detached HEAD, `result_for` returns `skipped:detached` before any fetch and does not set
   `promote_backlog_unknown`. The previous-state fallback then supplies `upstream_ref`, so the backlog and promotable SHA come
   from unfetched local refs and are published as fresh. Observed in scratch: after a new upstream commit, the push carried
   `promote_backlog_commits 1` (truth 2), the old promotable SHA and `lookup_failed 0`. `skipped:operation-in-progress` takes the
   same early return (inferred).
4. Info: the state keeps a 7-character SHA and carry-forward resolves it with `merge-base --is-ancestor`; an ambiguous prefix
   (the repo already has one 7-char collision in about 9,500 commits) would give rc 128 and silently drop the carry.
5. Info: up to 10 `is-green` calls at up to 60 s each run under a lock treated as stale after 180 s, so a very slow GitHub could
   let two syncs overlap (inferred).

## Proposed fix (when chosen)

- Add a promtool group with the series at `0+0x20` and no alert expected.
- Add tests that reach the previous-state fallback (no `@{upstream}`) and the exception-handler carry.
- Treat any hub root result that did not fetch (not only `fetch_failed`) as unknown.
