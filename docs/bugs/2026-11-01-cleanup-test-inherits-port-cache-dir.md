# Bug: `k3dm_cleanup.bats` port-marker test fails under `codex-dispatch land` because it inherits `K3DM_PORT_CACHE_DIR`

**Status:** VERIFIED — `fcfa5623` (Codex; Claude review, independent verify)
**Fix commit:** fcfa5623
**Priority:** P3
**Severity:** low — test-only; it refuses any land whose fast gate selects `k3dm_cleanup.bats`, with no defect in the task under land
**Approval:** operator, 2026-11-01 ("go ahead to dispatch them according (parallel if possible)"; found while landing)
**Filed:** 2026-11-01
**Detected by:** Claude, landing `webhook-slash-command-starts-bot-thread` (fast gate log `land-fast-gate.log`)
**Affected:** `scripts/tests/bin/k3dm_cleanup.bats` (test "k3dm-cleanup removes old Packer artifacts and port markers only", ~line 197)
**Branch:** `k3d-manager-v1.43.13`

## Observed failure

The land fast gate (M4, 2026-11-01) reported `not ok 8 k3dm-cleanup removes old Packer artifacts and port markers only`,
at `[ ! -e "${port_dir}/old-marker" ]`. The same test passes 3 of 3 runs alone. With
`K3DM_PORT_CACHE_DIR=<any dir>` exported it fails every run.

## Root cause

`bin/k3dm-cleanup` reads `K3DM_PORT_CACHE_DIR="${K3DM_PORT_CACHE_DIR:-${HOME}/.cache/port}"`. The test overrides only
`HOME`, expecting the default path. `bin/k3dm-codex-dispatch` exports
`K3DM_PORT_CACHE_DIR=$run/state/port-cache` for the land tests (~line 803), so the script prunes that directory and
never sees the test's `old-marker`.

## Fix

In that test (and any other test in the file that relies on the `HOME` default), pass
`K3DM_PORT_CACHE_DIR="${port_dir}"` explicitly in the `run env ...` call. Do not change `bin/k3dm-cleanup` or the
dispatcher.

## Files

- `scripts/tests/bin/k3dm_cleanup.bats`

## What NOT to do

- Do not unset or rename the dispatcher's `K3DM_PORT_CACHE_DIR` isolation.
- Do not weaken the `old-marker` / `new-marker` assertions.

## Acceptance

```yaml
must:
  M1: the port-marker test passes with K3DM_PORT_CACHE_DIR unset and with it exported to an unrelated scratch directory
  M2: with K3DM_PORT_CACHE_DIR pointed at the test's port_dir, the old marker is removed and the new one kept (paired positive control)
must_not:
  N1: the test never prunes or reads a directory outside its BATS_TEST_TMPDIR (the unrelated directory's own old marker survives)
  N2: bin/k3dm-cleanup and bin/k3dm-codex-dispatch are unchanged
evidence:
  E1:
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: You will see bats run k3dm_cleanup.bats twice, once with K3DM_PORT_CACHE_DIR exported to a scratch dir holding an old marker (red on the pre-fix test, which fails at the old-marker assertion) and once unset, both passing, with the scratch dir's marker still present and git diff showing only the test file.
    what: bats scripts/tests/bin/k3dm_cleanup.bats
interface:
  - bin/k3dm-cleanup (env HOME, K3DM_PORT_CACHE_DIR, K3DM_PORT_RETENTION_DAYS)
  - scripts/tests/bin/k3dm_cleanup.bats
```

## Verification (2026-11-01, Claude)

- Landed as `fcfa5623` through `make codex-land`; the ledger records `land` and `verify` events for slug `2026-11-01-cleanup-test-inherits-port-cache-dir`.
- Offline evidence: `bats scripts/tests/bin/k3dm_cleanup.bats`: rc 0, 12/12 with `K3DM_PORT_CACHE_DIR` exported to an unrelated dir (whose old marker survived) and 12/12 with it unset; the pre-fix test is `not ok` with the variable set. `bin/` unchanged. Claude verified from the Acceptance block.
- Errors seen: none.
