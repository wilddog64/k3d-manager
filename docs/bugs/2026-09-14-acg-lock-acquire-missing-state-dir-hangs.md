# Bug: `_acg_lock_acquire` spins for the full timeout when the lock's parent directory is missing

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-14
**Status:** OPEN — ready for Codex
**Files:** `scripts/lib/provider.sh`, `scripts/tests/lib/provider_active_set.bats`, `scripts/tests/bin/cluster_up.bats`, `CHANGELOG.md`

## Problem

`scripts/tests/bin/cluster_up.bats` → "acg-up dry-run previews core and never crosses the Step 4 seam" hangs. It already hung on HEAD `35388b47` (v1.33.0), before any v1.34.0 change.

Reproduced 2026-09-14 with `bash -x bin/cluster-up` under a fresh `HOME` (`DRY_RUN=1 CLUSTER_PROVIDER=k3s-aws`, same stubs as the test):

```
+ _acg_lock_acquire .../home/.local/share/k3d-manager/hub-bootstrap.lock 600
+ mkdir .../home/.local/share/k3d-manager/hub-bootstrap.lock
+ [[ -f .../hub-bootstrap.lock/pid ]]
+ [[ 0 -ge 600 ]]
+ sleep 1
... (repeats once a second)
```

- `bin/cluster-up:339` calls `_acg_lock_acquire "${_ACG_STATE_BASE}/hub-bootstrap.lock" 600`.
- `_acg_lock_acquire` (`scripts/lib/provider.sh`) loops on `mkdir "${lockdir}"` **without `-p`**. When `${_ACG_STATE_BASE}` (`~/.local/share/k3d-manager`) does not exist yet, `mkdir` fails every time. No `pid` file exists either, so the stale-lock branch never runs. The loop sleeps for the whole 600 s timeout and then carries on without the lock.
- The test sets `HOME` to an empty temp dir, so it always takes this path. Nothing has created the state base by Step 3.5.
- The same thing happens on a real first run on a fresh machine: `make up` stalls silently for 10 minutes.
- With the state directory pre-created, the same dry-run exits 0 in seconds, and the stubs log only `k3d cluster list` and `kubectl config use-context`.

## Fix

### S1 — `scripts/lib/provider.sh`: create the lock's parent directory

Old:

```bash
    local lockdir="${1:-}" timeout="${2:-120}" waited=0
    [[ -z "${lockdir}" ]] && return 0
    while ! mkdir "${lockdir}" 2>/dev/null; do
```

New:

```bash
    local lockdir="${1:-}" timeout="${2:-120}" waited=0
    [[ -z "${lockdir}" ]] && return 0
    mkdir -p "$(dirname "${lockdir}")" 2>/dev/null || true
    while ! mkdir "${lockdir}" 2>/dev/null; do
```

Change nothing else in the function. `mkdir -p` on the **parent** keeps the lock atomic, because the lock itself is still a plain `mkdir`.

### S2 — `scripts/tests/lib/provider_active_set.bats`: regression test

Add this test directly after the test `"_acg_lock_acquire with an empty lock dir is a no-op success"`:

```bash
@test "_acg_lock_acquire creates a missing parent directory instead of spinning" {
  local lk="${BATS_TEST_TMPDIR}/absent/state/hub.lock"
  run timeout 10 bash -c 'source "$1"; _warn() { :; }; _acg_lock_acquire "$2" 600' _ "${BATS_TEST_DIRNAME}/../../lib/provider.sh" "${lk}"
  [ "$status" -eq 0 ]
  [ -d "${lk}" ]
  [ -f "${lk}/pid" ]
}
```

`timeout 10` turns a regression into a failure (exit 124) instead of a 600 s hang. If `provider.sh` cannot be sourced standalone like this, look at how the file's `setup()` loads it, do the same inside the `bash -c` body, and report what you changed.

### S3 — `scripts/tests/bin/cluster_up.bats`: fix the silent negation at the end of the dry-run test

This is the last line of the test, so it does fail today. Convert it anyway, so the file has no bare `!` assertions left (see `docs/bugs/2026-09-14-bats-bare-negation-assertions-never-fail.md`).

Old:

```bash
  ! grep -q 'MUTATION:' "${stub_log}"
}
```

New:

```bash
  run grep -q 'MUTATION:' "${stub_log}"
  [ "$status" -ne 0 ]
}
```

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, as the last bullet:

```
- `_acg_lock_acquire` now creates the lock's parent directory, so a first `make up` on a machine without `~/.local/share/k3d-manager` no longer spins silently for the full 600 s hub-bootstrap lock timeout; this was also the cause of the hanging `cluster_up.bats` dry-run test
```

## Definition of Done

- [ ] S1–S3 applied; no other lines changed.
- [ ] `shellcheck -x scripts/lib/provider.sh`: no new warnings (paste the before/after counts).
- [ ] `timeout 300 bats scripts/tests/bin/cluster_up.bats scripts/tests/lib/provider_active_set.bats`: all pass, no timeout (paste the summary line).
- [ ] CHANGELOG bullet added.
- [ ] Commit message, verbatim: `fix(provider): create lock parent dir so hub-bootstrap lock never spins on a fresh HOME`

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT change `bin/cluster-up`, the lock timeout values, or `_acg_lock_release`.
- Do NOT run `bin/cluster-up` without `DRY_RUN=1` and stubbed binaries. Do not touch any live cluster.
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or memory-bank.
