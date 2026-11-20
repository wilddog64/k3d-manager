# Bug: "Tokens by repo" shows a scratchpad directory name (`m8src`) as a repo

**Status:** OPEN — captured 2026-11-19 by Claude
**Priority:** P3
**Introduced by:** unknown
**Should have been caught by:** unknown
**Introducing change reviewed:** unknown
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
