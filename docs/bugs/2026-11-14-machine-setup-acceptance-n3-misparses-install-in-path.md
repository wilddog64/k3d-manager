# Bug: machine-setup acceptance N3 fails when the repo path contains `install-`

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-14
**Severity:** low, test-only. Two N3 tests in `scripts/tests/bin/machine_setup_acceptance.bats` fail when the checkout or `TMPDIR` path contains `install-`.
**Filed:** 2026-11-14
**Detected by:** Claude, while landing promtool Part B
**Introduced by:** unknown
**Should have been caught by:** offline test
**Prior art:** not run (`find-similar-docs` unavailable: vector store down); exact-slug glob found nothing

## Evidence

Claude, m4-air, 2026-11-14, base `feb41165`:

    TMPDIR=<worktrees>/v1.44.0/2026-11-09-promtool-tests-need-pinned-install-on-every-host.run/state/tmp bats scripts/tests/bin/machine_setup_acceptance.bats
    not ok 35 N3: console only runs install-* named in agents.console.list, never a hub-only agent
    not ok 36 N3: worker only runs install-* named in agents.worker.list

- Under a `TMPDIR` without `install-` in its path, both pass (7/7 N3/N4).
- The tests take the first `install-[a-z0-9-]+` match on each logged `make` line. That line carries the fixture tree path, and in this run the path contains the slug `...-pinned-install-on-every-host`, so the match is `install-on-every-host`, not the make target.
- `codex-dispatch land` exports `TMPDIR=$run/state/tmp`, so any dispatch slug containing `install-` fails these tests at land.

## Fix (proposal)

Match the make target, not the first token: for example, take the last word of the line, or anchor the match to whitespace, `(^| )install-[a-z0-9-]+( |$)`.
