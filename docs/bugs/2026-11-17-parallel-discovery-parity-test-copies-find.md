# Bug: the parallel-discovery parity test compares against its own copy of the dispatcher's `find`

**Status:** OPEN
**Priority:** P3 — test-only; the test can stay green while the two discoveries drift apart.
**Triage:** backlog — pull into a release that already touches `scripts/tests/bin/makefile_test_all.bats` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** 46ec5b36 (v1.44.0, `docs/plans/v1.44.0-parallel-offline-tests.md`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Test-only defect where the parallel discovery parity test compares against a pasted copy of the `find` logic instead of running the dispatcher's discovery.)
**Waiting on:** operator decision
**Prior art:** none above threshold — exact-slug glob found nothing; `make find-similar-docs` not run (vector store needs the k3d-k3d-cluster context, absent on the M4)
**Filed:** 2026-11-17 (found by the Part B independent verifier, 2026-11-15)

## What happened

`scripts/tests/bin/makefile_test_all.bats:1007` (test `B1: parallel stage 1 discovery matches scripts/k3d-manager:439-443 discovery`) builds its expected list with a pasted copy of the dispatcher's search (`search_dirs=(lib core plugins etc)`, `find … -maxdepth 1 -type f -name '*.bats' | sort`, lines 1022-1027) instead of asking `scripts/k3d-manager` for its list. If the dispatcher's discovery changes (`scripts/k3d-manager:437-442`), the test still compares the Makefile against the old copy and stays green: it proves parity with itself, not with the dispatcher.

## Fix

Derive the expected list from `scripts/k3d-manager` itself, run against the fake repo: copy `scripts/k3d-manager` into `$FAKE_REPO/scripts/` and run its test discovery with `bats` stubbed to print its file arguments, so the list comes from the dispatcher's real code path. No production code changes.

## Acceptance

```yaml
must:
  - id: M1
    text: B1's expected file list is produced by running scripts/k3d-manager's discovery, not by a copy in the test
must_not:
  - id: N1
    text: B1 stays green when scripts/k3d-manager's search_dirs gains or loses a directory (red today with a scratch mutation — the copy does not follow it)
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: bats scripts/tests/bin/makefile_test_all.bats -f B1, then again with a scratch copy of scripts/k3d-manager whose search_dirs drops etc
    intent: "You will see the parity test pass on the real tree and fail when only the dispatcher's discovery is changed, so it now guards the real dispatcher."
interface: none
```

**Intent approved:** operator, 2026-11-17 ("approved")
