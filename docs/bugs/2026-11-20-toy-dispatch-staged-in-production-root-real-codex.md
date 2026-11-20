# Bug: a toy dispatch for a live check started in the production root with the real Codex

**Status:** OPEN — captured 2026-11-20; incident contained (worker stopped, run abandoned)
**Priority:** P3
**Introduced by:** pre-existing
**Should have been caught by:** none
**Introducing change reviewed:** no
**Waiting on:** operator decision — since 2026-11-20
**Prior art:** none — exact-slug glob only; `make find-similar-docs` unavailable (vector store needs the dead M4 k3d context), `git grep smartcd` hits are passing mentions only

## What happened

2026-11-20 ~07:55 PST, M4, while staging the child B E9 toy dispatch (`docs/bugs/2026-11-14-dispatch-stall-b-approval.md`).
Claude meant to start `e9-toy-approve` against a scratch worktree root with a stub worker:

`cd <repo> && export K3DM_WORKTREE_ROOT=<scratch> K3DM_CODEX_BIN=<stub> K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9; bin/k3dm-codex-dispatch start ...`

The smartcd hook makes `cd` return nonzero (`smartcd:15: command not found: _smartcd`) even though the directory changes, so `&& export`
was skipped and `start` ran with no override:

- worktree and run folder in the production root (`~/.local/share/k3d-manager/worktrees/v1.45.0/e9-toy-approve{,.run}`);
- the real Codex (`gpt-6.1-terra`) started on the child B spec; Claude killed it after ~15 s (`exited nonzero (143)`), worktree clean;
- production ledger: `start`, `primary_coordinator`, `identity`, `codex_exit`, `codex_usage` (input 45931, cached 31872, output 247), then
  `abandon` (operator "go 0"); metrics were scheduled against the production root, so the hub dispatch panels may count one abandoned run.

## Why it was possible

- The handoff warned that `cd` is broken by smartcd; the command still chained on `cd`'s exit code.
- Nothing checked where the run landed before the worker started: `start` detaches the worker immediately.

## Possible fixes (operator decision)

1. Process: toy or live-check dispatches always pass overrides inline (`env K3DM_WORKTREE_ROOT=... bin/k3dm-codex-dispatch ...`) and never
   chain on `cd`; put the recipe in `docs/howto/codex-dispatch.md`.
2. Tooling: a `--dry-run` (or `K3DM_DISPATCH_TOY=1` that refuses unless the root and worker bin are overridden) so a toy cannot reach the
   production root or a real model.
3. Environment: fix the smartcd hook on the M4 so `cd` returns 0 (dotfiles).
