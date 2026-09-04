# `e2e_runner_dispatch` reports a fresh M2 runner as "busy (lock held)" when the lock parent dir is missing (2026-08-22)

**Severity:** medium (false-positive dispatch block on any runner that has not yet
completed a run; the failure text misdirects to the unlock path, which is a no-op).
**Component:** `scripts/plugins/e2e_remote.sh` — `_e2e_remote_lock_acquire` (line ~298–301).
**Found while:** running the v1.27.0 plan #2 live-acceptance passing run against the M2
OrbStack runner (`make e2e-remote RUNNER=m2`).

## Symptom

`make e2e-remote RUNNER=m2` passes preflight (`runner m2 available`) but then fails:

```
INFO: [e2e-remote] runner m2 available; dispatching E2E (digest=none)
ERROR: [e2e-remote] runner m2 is busy (lock held); not dispatching, no local fallback
```

`make e2e-runner-unlock RUNNER=m2` disagrees — `no lock present on m2; nothing to clear` —
and `make e2e-runner-health RUNNER=m2` reports `runner_status=available`. Three code
paths give three different answers for the same runner.

## Root cause

The runner lock is a `mkdir`-based directory lock at `E2E_M2_LOCK`
(`$HOME/.k3dm/e2e/runner.lock`). `_e2e_remote_lock_acquire` runs a **bare** `mkdir`
(no `-p`) and treats **any** non-zero return as "another racer holds the lock":

```bash
_e2e_remote_ssh "mkdir \"${E2E_M2_LOCK}\" 2>/dev/null && printf '%s\n' \"${token}\" > \"${E2E_M2_LOCK}/meta\""
```

If the **parent** directory `$HOME/.k3dm/e2e` does not exist, `mkdir` fails with
`ENOENT` ("No such file or directory"), not `EEXIST`. The acquire cannot tell the two
apart, so a *missing parent* is misreported as a *held lock*.

Verified live on M2 (2026-08-22):

```
$ ssh m2jump 'mkdir "$HOME/.k3dm/e2e/runner.lock"'
mkdir: /Users/cliang/.k3dm/e2e: No such file or directory   # parent absent → rc=1
```

The parent is never guaranteed to exist before the first successful run:

- `e2e_runner_bootstrap` (line ~248) starts OrbStack, reconciles the cluster, and
  verifies the vcluster CLI — it does **not** create `$HOME/.k3dm/e2e`.
- `E2E_M2_REMOTE_REPORT_DIR` (`$HOME/.k3dm/e2e`) is `mkdir -p`'d only by the remote
  E2E run itself, which executes **after** the lock is acquired.

So on any runner that has not yet completed a run, the lock acquire fails 100% of the
time and the operator is pointed at `e2e-runner-unlock`, which correctly finds nothing
to clear (`[ -e $LOCK ]` is false) — a dead end.

The `unlock`/`health` paths use `[ -e "$LOCK" ]` (line 126, 735), which is `false` for
a missing lock — consistent with reality; only `acquire` conflates ENOENT with EEXIST.

## Fix

Ensure the lock parent exists before the atomic `mkdir` of the leaf, keeping the leaf
`mkdir` non-`-p` so it stays an atomic claim:

```bash
function _e2e_remote_lock_acquire() {
  local token="$1"
  _e2e_remote_ssh "mkdir -p \"${E2E_M2_LOCK%/*}\" && mkdir \"${E2E_M2_LOCK}\" 2>/dev/null && printf '%s\n' \"${token}\" > \"${E2E_M2_LOCK}/meta\""
}
```

`${E2E_M2_LOCK%/*}` strips the `/runner.lock` leaf M4-side on the literal
(`\$HOME/.k3dm/e2e`), and `$HOME` still expands remotely. The `mkdir -p` on the parent
is idempotent; the leaf `mkdir` remains the atomic race arbiter (still non-`-p`, still
`EEXIST` == genuinely busy).

Optionally also create the state dir in `e2e_runner_bootstrap` so a bootstrapped runner
is fully provisioned:

```bash
_e2e_remote_ssh "mkdir -p \"${E2E_M2_REMOTE_REPORT_DIR}\""
```

## Verification

- BATS: a unit test that asserts the acquire command string contains `mkdir -p` for the
  parent before the leaf `mkdir` (the module already unit-tests command construction).
- Live: on a runner with `$HOME/.k3dm/e2e` absent, `make e2e-remote RUNNER=m2` proceeds
  past the lock instead of reporting "busy"; a second concurrent dispatch still gets a
  genuine "busy" (leaf `mkdir` EEXIST).

## Related runner-provisioning gap (separate follow-up, not this fix)

The same acceptance run exposed that the M2 repo checkout is stale
(`k3d-manager-v1.7.2`, `e2e_verify_vcluster`/`e2e_runner_publish_back` absent) and M2
has no GitHub fetch access (`git@github.com: Permission denied (publickey)`). Dispatch
assumes the runner repo is already at the dispatched revision — there is no repo-sync
step. Decide whether `e2e_runner_bootstrap` should pin/sync the runner repo to a
revision, and how M2 authenticates to GitHub, without persisting an M4 credential on M2
(plan security constraint: no M4 kubeconfig/Vault/Cloudflare/Keychain secret on M2).
