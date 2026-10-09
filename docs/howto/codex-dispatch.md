# Codex dispatch

`bin/k3dm-codex-dispatch` gives each spec a separate worktree and task branch. Run it from a clean, pushed release branch:

```bash
make codex-dispatch SPEC=docs/plans/v1.43.0-example.md
make codex-status
```

Review the task worktree, run the spec's gates, and commit the verified changes in that worktree. Then return to the operator checkout and land it:

```bash
make codex-land SLUG=example
git push origin k3d-manager-v1.43.0
```

Codex never commits: Claude or the operator verifies the diff, gates, and scope before creating the one commit. Landing refuses any changed path not listed in the spec's `## Files` table, and always refuses `memory-bank/**`, even when the spec lists it. The spec path is recorded at start in `<run>/spec`, so scope is always judged against the dispatched spec. For an intentional scope exception, run `bin/k3dm-codex-dispatch land --slug <slug> --allow-out-of-scope` only after review; otherwise fix or remove the extra change in the worktree and retry.

Everything for a task lives under `~/.local/share/k3d-manager/worktrees/<version>/` (override with `K3DM_WORKTREE_ROOT`): the worktree `<slug>/` on branch `task/<version>/<slug>`, and the run folder `<slug>.run/` holding `prompt.md`, `codex.log`, `last-message.md`, `pid`, `exit` and a private `state/` directory. Codex gets `K3DM_REPO_ROOT`, `K3DM_JOB_DIR`, `K3DM_RUN_DIR`, `K3DM_STATE_DIR`, `K3DM_LOG_DIR`, `K3DM_TMP_ROOT`, `K3DM_PORT_CACHE_DIR` and `TMPDIR` pointed into that folder, so it never touches the live webhook's state.

Two tasks can run in parallel with different slugs. Each has its own worktree and state directory, though two full suites compete for CPU.

To remove an abandoned task, preview first and then confirm:

```bash
make codex-abandon SLUG=example
make codex-abandon SLUG=example YES=1
```

Worktree caveats:

- Gitignored files such as `.envrc`, `bin/.ask-sandbox/`, `node_modules` and `.wrangler` are not in a new worktree. Anything that needs them fails there.
- A branch can be checked out in only one worktree at a time.
- `git worktree prune` cleans up stale entries.
