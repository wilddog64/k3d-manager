# Bug: machine-setup N3 tests read an `install-*` token from the temp path, so a dispatch slug starting `install-` fails the land gate

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-11 (post-merge `/release-groom` triage: patch `v1.43.16` or carry into `v1.44.0`)
**Severity:** test-only. A false red in the land fast gate; no product effect. Workaround: run `scripts/ci/fast_gate.sh` with a neutral `TMPDIR`, then land with `K3DM_SKIP_FAST_GATE=1`.
**Introduced by:** `bd68d6ff` (v1.43.12, N3 tests added)
**Should have been caught by:** review
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run (vector store context missing on the M4, 2026-11-11). Related, different root cause: `docs/bugs/2026-10-31-machine-setup-acceptance-copies-whole-working-tree.md`.
**Approval:** Claude, 2026-11-11 (found while landing `install-agent-load-zero-no-bootout`)
**Filed:** 2026-11-11
**Detected by:** Claude, land fast gate for `install-agent-load-zero-no-bootout`, 2026-11-11
**Branch:** `k3d-manager-v1.43.15`

## What happened

`bin/k3dm-codex-dispatch land --slug install-agent-load-zero-no-bootout` failed its fast gate twice on
`scripts/tests/bin/machine_setup_acceptance.bats` (`not ok 35` / `not ok 36`, the two "only runs install-* named in
agents.<role>.list" tests). The same file passed when run directly in the same worktree.

## Root cause

Land runs the gate with `TMPDIR=<worktrees>/<version>/<slug>.run/state/tmp`. The N3 tests take the target from each
recorded make line with `grep -oE 'install-[a-z0-9-]+' | head -1` (`machine_setup_acceptance.bats:460,470`). When the
recorded line contains a path under that `TMPDIR`, the first match is the slug directory `install-agent-load-zero-no-bootout`,
which is not in `agents.console.list` or `agents.worker.list`.

Reproduced on m4-air, 2026-11-11, same tree (`bc09f24f`):
`TMPDIR=<slug>.run/state/tmp bats -f 'N3: console only' ...` rc=1; with a scratch `TMPDIR` rc=0. Full fast gate with
a neutral `TMPDIR`: rc=0, 45 PASS.

## Fix

Take the make target as a whole word after `make` (for example the last `install-*` argument, or match
`(^|[[:space:]])install-[a-z0-9-]+([[:space:]]|$)`), not the first `install-` substring anywhere in the line. Add a
test that runs the N3 pair with a `TMPDIR` containing `install-x` and expects green. Acceptance block to be added
before dispatch.
