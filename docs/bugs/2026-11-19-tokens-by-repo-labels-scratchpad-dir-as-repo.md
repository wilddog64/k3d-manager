# Bug: "Tokens by repo" shows a scratchpad directory name (`m8src`) as a repo

**Status:** OPEN — captured 2026-11-19 by Claude
**Priority:** P3
**Introduced by:** unknown
**Should have been caught by:** unknown
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Cosmetic dashboard labeling issue where non-worktree scratchpad runs and mismatched-version deleted worktrees appear as `m8src` or `other` in "Tokens by repo".)
**Waiting on:** operator decision — since 2026-11-19
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unreachable from this laptop).
**Approval:** none yet (capture only)

## Symptom

The agent-activity dashboard's "Tokens by repo" panel (`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`)
lists `m8src` (215 K tokens) next to k3d-manager, dirused, other and lib-foundation (operator screenshot, 2026-11-19).

`m8src` is not a repo. It is the working directory of an Astra (codex `gpt-6.2-astra`) review run on 2026-11-18
(`~/.codex/sessions/2026/11/18/rollout-2026-11-18T13-24-01-…jsonl`, `cwd` =
`/private/tmp/claude-501/…/90383cf6-…/scratchpad/m8src`), which Claude started on a scratch copy of the dirused M8
(`/purge`) source. The tokens belong to dirused.

## Fix direction (for triage)

Confirmed in code: `bin/k3dm-dispatch-metrics:680-684` labels a codex session by `_worktree_repo(cwd)` (dispatch
worktrees) and otherwise by `Path(cwd).name`, so any non-worktree `cwd` becomes its directory name. "other" in the
same panel is `_worktree_repo` returning "other" (a dispatch worktree whose `.git` is not a linked-worktree file,
`:612-645`) or a name failing `[A-Za-z0-9._-]{1,64}` (`:683`). Map a `cwd` under a Claude
scratchpad (`/private/tmp/claude-*/…/scratchpad/`) to `other`, or have review runs on scratch copies pass the source
repo name; or start such runs from a directory named after the repo.

## Also: what "other" holds (Claude, 2026-11-20)

The 7-day "other" bar (6.45 M, operator screenshot 2026-11-20) is a single dispatch,
`2026-11-12-hub-promote-containment-check-blind-to-squash-merges`. Its Codex sessions ran in
`worktrees/v1.44.0/<slug>`, but every ledger event for the slug says `version: v1.44.1`, so
`_dispatch_worktree_repos` has no `(v1.44.0, slug)` key. The worktree is deleted after landing, so
`_worktree_repo` finds no `.git` file and returns "other" (`bin/k3dm-dispatch-metrics:594-645`). In 30 days, "other"
also holds 2.88 M from `worktrees/manual/vectordb-ticks`, a worktree with no ledger start. Reproduced by running
the exporter's own `_session_files` with the ledger mapping on m4-air (7d: k3d-manager 475.9 M, dirused 79.1 M,
other 6.45 M, lib-foundation 6.28 M, m8src 0.21 M). Fix direction: map by slug when the version key misses, and
count a deleted dispatch worktree as `k3d-manager` (the ledger default) instead of "other".
