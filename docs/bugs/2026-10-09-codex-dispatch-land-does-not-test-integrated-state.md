# Bug: `codex-dispatch land` does not test the integrated state, and parallel tasks can share live resources

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** FIXED `c0871808` 2026-10-09 (Codex via worktree dispatch; Claude verified 28/28 BATS, shellcheck clean, six mutations red). Claude's changes: the scope diff now starts at the merge-base with the release branch, because a `land` retried after a test refusal saw the release branch's newer commits as task changes and refused the retry as out of scope; a resume refused by the network check no longer deletes the finished task's `exit`; tests added for the `--test false`/`true` retry, `--no-test` output, the lock after a test refusal, resume argv/cwd and every resume refusal.
**Priority:** P2 — parallel dispatch is live; a semantic conflict between two clean rebases would land untested
**Severity:** medium
**Origin:** operator, 2026-10-09, from a review of agent isolation: conflict handling,
serialized landing and shared-resource isolation.

## Symptom

`bin/k3dm-codex-dispatch` isolates source files, run state and the network. Three gaps remain once
tasks run in parallel:

1. **Semantic conflicts land untested.** `land` rebases the task onto the release branch and
   fast-forwards. A rebase conflict stops it. Two tasks that rebase cleanly but break each other
   (one renames a function, the other adds a caller) land with no test run. Claude's verification
   ran in the task worktree **before** the rebase, so it never saw the combined code.
2. **Landing is serialized only by habit.** Nothing stops two `land` calls from running at the
   same time against the operator checkout.
3. **`--network` is not exclusive.** Two tasks started with `--network` share the cluster,
   namespaces, Pushgateway and credentials (`HOME` is unchanged, so `~/.kube/config` is the same).
   This breaks the one-agent-per-live-sandbox rule.

## Fix

All in `bin/k3dm-codex-dispatch`.

### 1. `land` runs a test command on the rebased task before the fast-forward

- New options: `land --slug SLUG --test CMD` or `land --slug SLUG --no-test`. Exactly one is
  required. Neither, or both, is an error (exit 2). `--no-test` exists for docs-only tasks and
  prints `tests: skipped (--no-test)`.
- Order after this change: preconditions, scope, rebase, **test**, `merge --ff-only`, cleanup.
- The test runs as `bash -c "$CMD"` with the task worktree as the working directory, and with the
  same `_dispatch_state_vars` environment Codex had. That way a test cannot write to the live
  webhook state.
- Its output goes to `<run>/land-test.log`. The last 20 lines are printed on failure.
- On failure, `land` exits 2 with `tests failed after rebase onto <rel>; see <run>/land-test.log`.
  The operator checkout is not touched. The task branch stays rebased, so a fix can be committed
  in the worktree and `land` run again.
- On success it prints `tests: passed`, then continues as today.

### 2. A landing lock

- Before the operator-checkout checks, take a lock: `mkdir "$_dispatch_worktree_root/$version/.land.lock"`
  and write the current PID into `pid` inside it.
- If `mkdir` fails and the recorded PID is alive, exit 2 with
  `another land is in progress (pid N)`. If the PID is dead, remove the stale lock once and retry.
- Release the lock with a `trap … EXIT` set immediately after it is taken, so every exit path
  releases it, including errors.

### 3. `--network` is exclusive

- `start --network` writes `<run>/network`.
- Before launching, `start --network` scans `$_dispatch_worktree_root/$version/*.run/network`. If
  any of those runs has no `exit` file and its `pid` is alive, exit 2 with
  `network task <slug> is still running; only one networked task at a time`.
- A run without `--network` is never blocked.
- `status` prints `network: yes` for a networked task.

### 4. Make and docs

- `Makefile`, `codex-land`: pass `--test '$(TEST)'` when `TEST` is set, and `--no-test` when
  `NO_TEST=1`. With neither, the script's own error explains the choice.
- `docs/howto/codex-dispatch.md`:
  - the test-before-land step, with an example `TEST="bats scripts/tests/bin/codex_dispatch.bats"`;
  - the landing lock;
  - the networked-task rule;
  - a note that tests must not bind fixed local ports, because parallel tasks run tests at the same time;
  - `resume`, and when to use it rather than `abandon` and re-dispatch.
- `docs/howto/makefile.md`: update the `codex-land` row.

### 5. `resume`: send a follow-up to the same Codex session

Added 2026-10-09. Bug-priority tracking came back with no tests. Claude resumed the session by hand
with `codex exec resume`, rebuilding the environment and sandbox flags from memory. That should be
a subcommand.

- `resume --slug SLUG --prompt-file PATH`. `make codex-resume SLUG= PROMPT=`.
- **Refusals** (exit 2):
  - Codex is still running (live `pid` and no `exit`);
  - the task has landed (`<run>/landed`);
  - the worktree does not exist;
  - the prompt file is missing or empty;
  - no `session id:` line is found in `<run>/codex.log`.
- The session id is the first `^session id: ` value in `<run>/codex.log`. Validate it as a UUID.
- **Files.**
  - Number the resume: `n` = 2, 3, and so on.
  - Copy the prompt to `<run>/prompt-<n>.md`.
  - Log to `<run>/codex-<n>.log`, and write `-o <run>/last-message-<n>.md`.
  - Before launching, remove `<run>/exit`, so `status` and `land` see the task as running again.
  - Write the new pid to `<run>/pid`. Write `<run>/exit` when it finishes, exactly like `start`.
- **Launch.**
  - Use the same `_dispatch_state_vars` environment, the worktree as the working directory, and
    `</dev/null >/dev/null 2>&1 &` detachment as `start`.
  - Command: `codex exec resume -c sandbox_mode="workspace-write" -c 'sandbox_workspace_write.writable_roots=["<run>/state"]' -o <run>/last-message-<n>.md <id> - < <run>/prompt-<n>.md`.
  - Add `-c sandbox_workspace_write.network_access=true` only when `<run>/network` exists (item 3),
    and the networked-task check applies as in `start`.
  - `codex exec resume` has no `-C` or `--add-dir`. That is why the working directory and the
    writable root are set this way.
- **Status.** `status` shows `resumes: <n-1>` when any resume happened.
- **Scope is unchanged.** It still comes from the spec at `<run>/base`, so a resume prompt cannot
  widen it.

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | items 1–3, 5 |
| `scripts/tests/bin/codex_dispatch.bats` | regression tests |
| `Makefile` | `codex-land` passes `TEST` / `NO_TEST`; new `codex-resume` |
| `docs/howto/codex-dispatch.md` | item 4 |
| `docs/howto/makefile.md` | `codex-land` row; `codex-resume` row |

## Tests

Add to `scripts/tests/bin/codex_dispatch.bats`, using the existing fixture:
1. **Semantic conflict.**
   - Task A commits `a.txt` containing `v1`.
   - After A is dispatched, the release branch gets a commit adding `check.sh`, which runs
     `grep -qx v2 a.txt`. The two changes rebase cleanly but disagree.
   - `land --test 'bash check.sh'` exits 2, and the operator checkout's HEAD is unchanged.
2. `land --test true` lands. `land --test false` refuses, and the operator HEAD is unchanged.
3. `land` with neither `--test` nor `--no-test` exits 2. With both, it exits 2.
4. `land --no-test` lands and prints `tests: skipped (--no-test)`.
5. **The lock.**
   - With `.land.lock` held by a live PID (`sleep 30 &`), `land` exits 2 with
     `another land is in progress`.
   - With a dead PID in the lock, `land` succeeds.
   - After any `land` (success or failure), `.land.lock` does not exist.
6. **Network.**
   - With `STUB_SLEEP=5`, a second `start --network` while the first networked task runs exits 2.
   - A second `start` without `--network` succeeds.
   - After the first one's `exit` file appears, a new `start --network` succeeds.
7. The test command sees `K3DM_JOB_DIR` under `<run>/state`, not the operator's.
8. **Resume.** The stub Codex prints `session id: 01a122dd-71c3-7763-87f0-3de505f10168` on start
   and records its argv on every call.
   - After the first run exits, `resume --slug one --prompt-file p.md` launches the stub with
     `exec resume`, the session id, `writable_roots` naming `<run>/state`, and the working
     directory equal to the worktree.
   - `prompt-2.md`, `codex-2.log` and `last-message-2.md` exist. `exit` is re-created after the stub
     finishes.
   - With `STUB_SLEEP=5`, a resume while the first run is still running exits 2.
   - A resume of a landed task exits 2.
   - A resume when `codex.log` has no session id exits 2.
   - A second resume uses `n` = 3.
   - Without `<run>/network`, the argv has no `network_access=true`.

Mutation checks. Paste the red output for each:
- Move the test after `merge --ff-only`. Test 1 must fail (HEAD moved).
- Delete the lock `trap`. The "lock released after failure" part of test 5 must fail.
- Drop the `network` marker scan. Test 6 must fail.
- Skip removing `<run>/exit` before a resume. The "exit is re-created after the stub finishes" part of test 8 must fail.

## Rules

- `shellcheck bin/k3dm-codex-dispatch`: zero warnings.
- `bats scripts/tests/bin/codex_dispatch.bats`: all green. Paste the output.
- No test binds a fixed port.
- Do not commit. `.git` is read-only in the sandbox.
