# Codex dispatch

`bin/k3dm-codex-dispatch` gives each spec a separate worktree and task branch. Run it from a clean, pushed release branch:

```bash
make codex-dispatch SPEC=docs/plans/v1.43.0-example.md
make codex-status
```

Review the task worktree, run the spec's gates, and commit the verified changes in that worktree. Then return to the operator checkout and land it. `land` rebases first, runs the requested command on the rebased task, and only then fast-forwards:

```bash
make codex-land SLUG=example TEST="bats scripts/tests/bin/codex_dispatch.bats"
git push origin k3d-manager-v1.43.0
```

Use `NO_TEST=1` for a docs-only task; otherwise exactly one of `TEST` or `NO_TEST=1` is required. The landing lock serializes land operations. A `--network` task is exclusive: another networked task cannot start until its `exit` file exists, while non-networked tasks may still run. Tests must not bind fixed local ports because task tests can run in parallel.

Codex never commits: Claude or the operator verifies the diff, gates, and scope before creating the one commit. Landing refuses any changed path not listed in the spec's `## Files` table, and always refuses `memory-bank/**`, even when the spec lists it. The scope comes from the spec as dispatched, and editing the spec itself is out of scope. For an intentional scope exception, run `bin/k3dm-codex-dispatch land --slug <slug> --allow-out-of-scope` only after review; otherwise fix or remove the extra change in the worktree and retry.

Everything for a task lives under `~/.local/share/k3d-manager/worktrees/<version>/` (override with `K3DM_WORKTREE_ROOT`): the worktree `<slug>/` on branch `task/<version>/<slug>`, and the run folder `<slug>.run/` holding `prompt.md`, `codex.log`, `last-message.md`, `pid`, `exit` and a private `state/` directory. Codex gets `K3DM_REPO_ROOT`, `K3DM_JOB_DIR`, `K3DM_RUN_DIR`, `K3DM_STATE_DIR`, `K3DM_LOG_DIR`, `K3DM_TMP_ROOT`, `K3DM_PORT_CACHE_DIR` and `TMPDIR` pointed into that folder, so it never touches the live webhook's state.

Two tasks can run in parallel with different slugs. Each has its own worktree and state directory, though two full suites compete for CPU. If Codex finishes without implementing the spec, use `make codex-resume SLUG=example PROMPT=/path/follow-up.md` to continue the same session. Use `abandon` and re-dispatch only when the task should be discarded or its session cannot be resumed; resume does not change the recorded scope.

To remove an abandoned task, preview first and then confirm:

```bash
make codex-abandon SLUG=example
make codex-abandon SLUG=example YES=1
```

Worktree caveats:

- Gitignored files such as `.envrc`, `bin/.ask-sandbox/`, `node_modules` and `.wrangler` are not in a new worktree. Anything that needs them fails there.
- A branch can be checked out in only one worktree at a time.
- `git worktree prune` cleans up stale entries.

## Metrics

The dispatcher appends lifecycle events to the shared `K3DM_WORKTREE_ROOT/ledger.jsonl` and
publishes them to the hub Pushgateway with `make dispatch-metrics`. The exporter keeps 1d, 7d,
and 30d windows for the `k3dm Agent Dispatch` dashboard:

- Fleet throughput is landed tasks per day.
- Landing success is landed divided by landed plus refusals at the integration-test step.
- Human intervention is verifier lines changed after Codex, plus wall-clock waiting minutes from
  Codex exit to land. Waiting time is not active minutes.
- Agent efficiency is Codex tokens per landed task. It excludes Claude's verification tokens and
  is not converted to dollars because token pricing is not stable.

Use `make dispatch-metrics DRY_RUN=1` to render the Prometheus text without contacting
Pushgateway. The exporter uses the latest resumed Codex token total for a task.
