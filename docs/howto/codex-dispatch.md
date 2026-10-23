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

Everything for a task lives under `~/.local/share/k3d-manager/worktrees/<version>/` (override with `K3DM_WORKTREE_ROOT`): the worktree `<slug>/` on branch `task/<version>/<slug>`, and the run folder `<slug>.run/` holding `prompt.md`, `codex.log`, `supervisor.log`, `last-message.md`, `start`, `pid`, `exit`, `codex-exit-ts` and a private `state/` directory. The worker is launched in a detached session, so an agent-launched dispatch no longer requires the launching command to stay alive. `start` is written by the worker itself and records its PID and process start identity; `exit` and `codex-exit-ts` are written before Git, ledger or metrics bookkeeping. Startup and bookkeeping diagnostics go to `supervisor.log`; Codex's own output remains in `codex.log`.

`codex-status` reports `starting` while the detached worker has not acknowledged startup, `running` after the start marker is verified, `exited successfully` for exit code 0, and `exited nonzero (<code>)` for another Codex result. A worker with a start marker but no terminal marker is reported as `terminated unexpectedly (see .../supervisor.log)`, rather than remaining indefinitely `unknown`. `unknown` is reserved for runs that never produced a worker start marker.

Codex gets `K3DM_REPO_ROOT`, `K3DM_JOB_DIR`, `K3DM_RUN_DIR`, `K3DM_STATE_DIR`, `K3DM_LOG_DIR`, `K3DM_TMP_ROOT`, `K3DM_PORT_CACHE_DIR` and `TMPDIR` pointed into that folder, so it never touches the live webhook's state.

Two tasks can run in parallel with different slugs. Each has its own worktree and state directory, though two full suites compete for CPU. If Codex finishes without implementing the spec, use `make codex-resume SLUG=example PROMPT=/path/follow-up.md` to continue the same session. Use `abandon` and re-dispatch only when the task should be discarded or its session cannot be resumed; resume does not change the recorded scope.

To remove an abandoned task, preview first and then confirm:

```bash
make codex-abandon SLUG=example
make codex-abandon SLUG=example YES=1
```

## Landing while Claude is away

When Codex finishes a task and Claude is not available to review it, the operator can land it
with one command:

```bash
make codex-land-pending SLUG=example TEST="bats scripts/tests/plugins/example.bats"
```

It refuses unless the main checkout is on a clean release branch that is not behind `origin` and
the task's state is `exited successfully`. Then it:

1. commits the worktree with the message from the spec's `- [ ] Commit: \`...\`` line;
2. runs `codex-land` with `TEST` and pushes the release branch;
3. rewrites the spec's `**Status:**` line to `LANDED — Claude review pending (<sha>, <time>)`,
   appends a pending line to `memory-bank/progress.md`, commits that and pushes.

It never marks a task verified or fixed. Claude's review (tests shown red on the pre-fix code,
small fixes as new commits) and any live evidence follow when Claude is back, and only then does
the status change to FIXED. If the change touches dashboards, ApplicationSets, `platform-ops` or
the webhook, landing is safe, but hold `make appsets-reapply`, `make platform-ops` and
`make restart-webhook` until that review.

`land` tests the rebased commit before it is pushed, so a test that requires HEAD to be on
`origin` fails there. The four `e2e_remote.bats` dispatch tests do: give `TEST` a `bats -f`
filter that excludes them, and run the full suite after the push.

## Pruning old task worktrees

`make codex-prune` previews landed task worktrees and leftover task branches across every release
under `K3DM_WORKTREE_ROOT`. It keeps tasks with unapplied commits, uncommitted work, a live worker,
or no matching remote release branch. Run the preview first, then add `YES=1` to remove eligible
worktrees and branches. The command leaves every `.run` directory and its logs, plus the dispatch
ledger and metrics, untouched.

```bash
make codex-prune
make codex-prune YES=1
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
- Per-spec series include the latest Codex token total, Codex seconds summed across runs, elapsed
  seconds from the first start to land, and the number of Codex runs. They use validated version
  and slug labels only on these task series, with at most 50 newest landed tasks per window; the
  exporter exposes skipped and truncated counts. The two per-spec means cover all landed tasks,
  not only the displayed rows.

Use `make dispatch-metrics DRY_RUN=1` to render the Prometheus text without contacting
Pushgateway, including the per-task series. The exporter uses the latest Codex token total that a
task recorded.
