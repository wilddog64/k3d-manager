# Bug: `make up` aborts at Step 10g when sudo is not cached, although the loopback-alias failure was meant to be a warning

**Status:** OPEN
**Filed:** 2026-10-05
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Medium. A full `make up` dies at Step 10g, after about 30 minutes of work, and leaves a
billable CloudFormation stack running.
**Files:** `bin/cluster-up`, `scripts/tests/bin/sandbox_launchd_scope.bats`, `CHANGELOG.md`

## Symptom

From the operator's `make up` pane on 2026-10-05:

```
INFO: [acg-up] Step 10g/14 — Installing frontend HTTP listener (frontend.shopping-cart.local → 127.0.0.3:80 → ubuntu-k3s, auto-restart)...
ifconfig: ioctl (SIOCAIFADDR): permission denied
ERROR: failed to execute /sbin/ifconfig lo0 alias 127.0.0.3: 1
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
WARN: [acg-up] CloudFormation stack 'k3d-manager-cluster' (us-west-2) was created by this run and is still running — billable. Reclaim it with: make down
make: *** [up] Error 1
```

`lo0` had only `127.0.0.1` and `127.0.0.2`. The persistent daemon
`/Library/LaunchDaemons/com.k3d-manager.sandbox.loopback-alias.plist` was not installed.

## Root cause

`bin/cluster-up` (around line 1607):

```bash
  if ! /sbin/ifconfig lo0 | grep -q '127\.0\.0\.3'; then
    _run_command --prefer-sudo --quiet -- /sbin/ifconfig lo0 alias 127.0.0.3 || \
      _warn "[acg-up] failed to add 127.0.0.3 loopback alias — frontend port-forward will fail to bind"
  fi
```

- `--prefer-sudo` uses sudo only when credentials are already cached. Otherwise it runs as the user,
  and adding a `lo0` alias needs root.
- Without `--soft`, `_run_command` reports a failure through `_err`, which **exits**. The `|| _warn`
  fallback can never run, so a step written as best-effort aborts the whole run.

The persistent-daemon install a few lines below already uses
`_run_command --interactive-sudo --quiet --soft`. That form prompts on the operator's TTY when sudo
is not cached, and returns instead of exiting. The alias call is the only one in the block without
it.

## Fix spec

### File 1 — `bin/cluster-up`

Replace:

```bash
    _run_command --prefer-sudo --quiet -- /sbin/ifconfig lo0 alias 127.0.0.3 || \
```

with:

```bash
    _run_command --interactive-sudo --quiet --soft -- /sbin/ifconfig lo0 alias 127.0.0.3 || \
```

No other line changes.

### File 2 — `scripts/tests/bin/sandbox_launchd_scope.bats`

Add a test, **"cluster-up loopback alias failure is soft and can prompt for sudo"**:

- `run grep -nF -- '--interactive-sudo --quiet --soft -- /sbin/ifconfig lo0 alias 127.0.0.3' bin/cluster-up`;
  expect status 0.
- `run grep -nF -- '--prefer-sudo --quiet -- /sbin/ifconfig lo0 alias' bin/cluster-up`; expect
  status 1.

### File 3 — `CHANGELOG.md`

Under `## [Unreleased]` → `### Fixed`, add a prose entry:

- Step 10g adds the `127.0.0.3` loopback alias with `--prefer-sudo` and no `--soft`.
- When sudo was not cached, that call failed as a non-root user and `_run_command` exited. The
  intended warning never ran, and `make up` aborted with the stack still running.
- The call now uses `--interactive-sudo --soft`, like the daemon install beside it. It prompts on
  the TTY and, if it still fails, warns and continues.

Flip this file's **Status** to FIXED.

## Definition of Done

- [ ] Pre-fix proof: the new test is RED at `HEAD`; paste the output.
- [ ] Mutation: remove `--soft` from the new line; the test goes red. Restore from a `$TMPDIR`
      snapshot and prove the restore with `cmp`.
- [ ] `bats scripts/tests/bin/sandbox_launchd_scope.bats` is green; paste the counts.
- [ ] `shellcheck bin/cluster-up` shows no new findings vs `HEAD`.
- [ ] Changes are left **unstaged**. Claude verifies and commits.

## What NOT to do

- Do NOT run `make up`, `bin/cluster-up`, `ifconfig`, `sudo`, `launchctl` or anything live.
- Do NOT change any other `_run_command` call or the daemon install block.
- Do NOT touch files outside those listed. Do NOT touch other unstaged changes. No commit, push,
  PR or `--no-verify`.
