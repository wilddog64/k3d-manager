# dispatch_stall_watch.bats E4 checks only that errors.txt is non-empty, not that the git captures failed

**Status:** OPEN — captured 2026-11-17 from Argon's blind review of PR #162 (v1.44.1), verified by Claude
**Priority:** P3 — test strength only
**Introduced by:** c91b4409 (stall detector A2, k3d-manager-v1.44.1)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-17

## Symptom

"E4: missing notifier and failed git still leave evidence and ledger" (`scripts/tests/bin/dispatch_stall_watch.bats`, ~line 226) asserts `[ -s "$dir/errors.txt" ]` but not which capture failed. It relies on the test tree not being a git repo; if the temp dir sat inside a git tree, `git status` would succeed and the test could pass for a different reason.

## Verified by Claude (2026-11-17)

Read the test: no `grep` for the status or diff failure lines, and no `GIT_CEILING_DIRECTORIES`. The test passes today because the BATS temp dir is outside any git tree.
