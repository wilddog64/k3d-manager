# deploy/hub behind counts docs-only commits and asks for promotes that change nothing

**Status:** OPEN — captured 2026-11-13 (operator asked what "backlog 9" meant, then "move this to P3 bug doc")
**Priority:** P3 (proposed: misleading tile and a nagging warning; no wrong deploy, the hub is unaffected)
**Classified:** pending second-agent classification
**Introduced by:** c763e239 (plan 3 `deploy-hub-behind-alert`)
**Should have been caught by:** spec
**Prior art:** exact-slug glob, none (closest by name `2026-11-13-deploy-hub-behind-alert-r2-test-gaps-and-detached-head.md`, read, different root cause); `make find-similar-docs` not run (vector store unavailable on m4-air)
**Waiting on:** operator decision

## Symptom

The Bugs dashboard tile "deploy/hub behind" (`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml:2973`) showed
backlog 9, then 12, with promotable `851e183`, on 2026-11-13. Every one of the 15 commits on `k3d-manager-v1.44.0` not on
`deploy/hub` (5c253d1b) was docs or memory-bank (7 files: bug docs, `docs/ideas.md`, a plan doc, `memory-bank/`). The tile
goes red at 1, and `K3dmPromoteWaiting` (`scripts/etc/prometheus/rules/repo-sync.yaml`) fires after 15 minutes asking for
`make hub-promote REF=851e1837`, a promote that would change nothing the hub runs.

## Cause

The backlog is `git rev-list --count <remote>/deploy/hub..<upstream>` (`bin/k3dm-repo-sync:461`) and the promotable SHA is
the newest CI-green commit, both over all paths. Plan 3's spec asked for the commit count, so the code is as specified.

"Promotes behind" is not a usable replacement: a promote fast-forwards `deploy/hub` past every earlier commit, so any
backlog is one promote away.

## Proposed fix

1. Headline count: commits behind that touch hub-deployed paths, reusing `scripts/etc/machine/deploy-paths.tsv` (already
   read at `bin/k3dm-repo-sync:389` for the webhook-restart step). No second path list.
2. Keep the all-commits count as a small context value, not the red headline.
3. Optional: age of the oldest hub-relevant unpromoted commit.
4. `K3dmPromoteWaiting` fires only when the promotable SHA carries at least one hub-relevant commit.

Check first that `deploy-paths.tsv` covers everything the hub reads from `deploy/hub` (ApplicationSets, platform-ops,
`bin/`, `scripts/`); a missing prefix would read 0 while real changes wait. The "docs-only reads 0" test needs a positive
control (a code commit reads 1), per the test-controls rule.

## Contract readers

To be listed by grep at spec time: `k3dm_repo_sync_promote_backlog_commits`, `k3dm_repo_sync_promotable`, the Bugs
dashboard tile, `K3dmPromoteWaiting`, the hub-sync summary line (`promote backlog: N; promotable: <x>`, asserted in
`scripts/tests/bin/repo_sync.bats`), and `scripts/tests/bin/test_dashboard_queries.py`.
