# Bug: CI `stage2` on the M2 ignores the e2e runner lock, so it can run alongside a remote e2e

**Status:** FIXED — `d478ed59` (Luna); live check E3 pending a `ci:cluster-tests` PR
**Priority:** P3
**Approval:** operator, 2026-10-30 ("we just want to ensure … only one can be executed"; "go ahead")
**Filed:** 2026-10-30
**Detected by:** Claude (reading `.github/workflows/ci.yml` and `scripts/plugins/e2e_remote.sh` while
answering the operator's control-node question)
**Affected:** `.github/workflows/ci.yml` job `stage2`; the M2 runner lock (`~/.k3dm/e2e/runner.lock`)
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/plans/v1.27.0-m2-remote-e2e-runner.md` (the lock's origin)

## Observed failure

The M2 serves two kinds of work:

1. **Remote Tier 1 e2e** (`make e2e-remote RUNNER=m2`, `scripts/plugins/e2e_remote.sh`). It claims
   `~/.k3dm/e2e/runner.lock` on the M2 with an atomic `mkdir` and refuses to start when the lock is held.
2. **The GitHub Actions self-hosted runner** (`actions.runner.wilddog64-k3d-manager.m2-air`), which runs
   the CI job `stage2` (`runs-on: [self-hosted, macOS, ARM64]`) on PRs labelled `ci:cluster-tests`.

`stage2` never looks at the lock and never takes it. A `stage2` job and a remote e2e can therefore run at
the same time on the M2, competing for Docker/OrbStack, CPU and memory. The operator wants exactly one of
them running at a time. `stage2` runs rarely (none of the last 15 CI runs reached it), so this has not
been seen live; it is a latent overlap.

Remote e2e is the primary user of the M2: it never waits for CI, it fails fast when busy (unchanged).
CI is the backup: it waits for the lock.

## Fix

### New `scripts/ci/runner_lock.sh`

`set -euo pipefail`. Runs **on the M2** inside the `stage2` job. Usage:

- `scripts/ci/runner_lock.sh acquire` — claims the same lock directory the remote e2e uses:
  `${E2E_RUNNER_LOCK:-$HOME/.k3dm/e2e/runner.lock}` (create the parent with `mkdir -p`; claim the lock
  itself with a plain `mkdir`, which is atomic). On success it writes `meta` with the token
  `owner=ci-<GITHUB_RUN_ID>-<GITHUB_RUN_ATTEMPT> pid=<pid> ts=<epoch>` (same shape as
  `_e2e_lock_token`, no shell metacharacters) and prints the token on stdout. When the lock is held it
  polls every `${CI_RUNNER_LOCK_INTERVAL:-30}` seconds up to `${CI_RUNNER_LOCK_WAIT:-1800}` seconds, then
  exits 1 with `runner busy: <contents of meta, or "holder unknown">` on stderr. It never removes a lock
  it does not own.
- `scripts/ci/runner_lock.sh release TOKEN` — removes the lock directory only when `meta` contains
  exactly `TOKEN` as a whole line (`grep -qxF`), as `_e2e_remote_lock_release` does. Otherwise it does
  nothing and exits 0.
- Any other usage: message on stderr, exit 2.

### `.github/workflows/ci.yml` job `stage2`

- Add `timeout-minutes: 90` to the job, so a CI hold stays under `E2E_M2_LOCK_MAX_AGE` (7200 s) and the
  guarded `make e2e-runner-unlock` never sees a live CI lock as stale.
- After `Checkout` and before `Cluster health check`, add a step `Acquire M2 runner lock` (`id:
  runner_lock`) that runs `scripts/ci/runner_lock.sh acquire` and writes the token to
  `$GITHUB_OUTPUT` as `token`.
- Add a final step `Release M2 runner lock` with
  `if: ${{ always() && steps.runner_lock.outputs.token != '' }}` that runs
  `scripts/ci/runner_lock.sh release "$TOKEN"`, with `TOKEN` passed through `env:` from
  `steps.runner_lock.outputs.token` (not interpolated into the script body).
- Leave every other line of `stage2`, and every other job, unchanged.

### `scripts/plugins/e2e_remote.sh`

Only the busy reason text in `_e2e_remote_eval_gates`: change `an E2E run already holds the runner lock`
to `another run (E2E or CI) holds the runner lock`. Nothing else in this file changes.

### Docs

`docs/howto/cloud-session-requests.md`, section **Remote-runner contention**: one short paragraph saying the CI `stage2` job takes the same
lock, waits up to 30 minutes for it, and that remote e2e never waits.

**As landed (Claude's review, 2026-10-30).** Landed as Luna wrote it. 7/7 tests pass; shellcheck and
actionlint clean. Mutations red on temp copies: claiming with `mkdir -p`, blind release, a timeout that
removes the lock, no wait, usage exit 1; and on `ci.yml`: no `always()`, the token interpolated into the
script, no `timeout-minutes`, and the pre-fix workflow.

## Files

- `scripts/ci/runner_lock.sh` (new)
- `.github/workflows/ci.yml`
- `scripts/plugins/e2e_remote.sh` (one string)
- `scripts/tests/ci/runner_lock.bats` (new)
- `scripts/tests/plugins/e2e_remote.bats` (only if a test asserts the old busy string)
- `docs/howto/cloud-session-requests.md` (section Remote-runner contention)
- `CHANGELOG.md` (one `### Fixed` line under `[Unreleased]`)

## What NOT to do

- Do not change the lock path, the token shape, `_e2e_remote_lock_acquire`, `_e2e_remote_lock_release`,
  `e2e_runner_unlock`, or `E2E_M2_LOCK_MAX_AGE`. Remote e2e must keep failing fast when busy; do not
  make it wait.
- Do not change `stage2`'s trigger condition, `runs-on`, or its test commands.
- Do not ssh anywhere, touch the real `~/.k3dm/e2e/runner.lock`, or run anything against the M2. Tests
  set `E2E_RUNNER_LOCK` under `$BATS_TEST_TMPDIR` and use short `CI_RUNNER_LOCK_WAIT` /
  `CI_RUNNER_LOCK_INTERVAL` values.
- Do not create a PR, commit to `main`, or skip hooks with `--no-verify`.
- Write the must_not tests first and show them red against a temp copy of the script with the guard
  removed (for N1–N3) and against the pre-fix `ci.yml` (for M3).

## Acceptance

```yaml
must:
  M1: runner_lock.sh acquire on a free lock creates the lock directory, writes meta with an owner=ci-<run id>-<attempt> pid= ts= token, prints that token, and exits 0.
  M2: runner_lock.sh acquire on a held lock waits, and succeeds once the holder releases within CI_RUNNER_LOCK_WAIT.
  M3: In ci.yml, stage2 acquires the lock before the cluster health check and integration tests, releases it in a step that runs on always(), passes the token through env, and has timeout-minutes of at most 119.
  M4: runner_lock.sh release TOKEN removes the lock when meta holds TOKEN.
  M5: docs/howto/cloud-session-requests.md, Remote-runner contention, says CI stage2 takes the same lock and waits, and remote e2e does not wait.
must_not:
  N1: acquire on a lock that stays held past CI_RUNNER_LOCK_WAIT exits non-zero, names the holder from meta, and leaves the lock and its meta unchanged.
  N2: release with a token that does not match meta leaves the lock in place.
  N3: Two concurrent acquires on a free lock never both exit 0 before one releases.
  N4: A bad subcommand or a missing release token exits 2.
evidence:
  E1: {proves: [M1, M2, M4, N1, N2, N3, N4], kind: offline, what: "bats scripts/tests/ci/runner_lock.bats with E2E_RUNNER_LOCK in BATS_TEST_TMPDIR"}
  E2: {proves: [M3], kind: offline, what: "a bats test parsing .github/workflows/ci.yml (yq or python3 yaml) for the stage2 step order, the always() release, the env-passed token and timeout-minutes; red on the pre-fix ci.yml"}
  E3: {proves: [M3], kind: live, what: "Claude or the operator: with a remote e2e holding the lock, a ci:cluster-tests PR's stage2 log shows it waiting, then running after release"}
interface:
  - scripts/ci/runner_lock.sh acquire|release TOKEN (env E2E_RUNNER_LOCK, CI_RUNNER_LOCK_WAIT, CI_RUNNER_LOCK_INTERVAL, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT)
  - .github/workflows/ci.yml job stage2
```
