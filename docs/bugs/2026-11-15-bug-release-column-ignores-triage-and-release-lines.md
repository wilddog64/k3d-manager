# Bug: the bug tables put every triaged bug in the release it was filed on, ignoring `**Triage:**` and `**Release:**`

**Status:** OPEN — captured 2026-11-15 by Claude
**Priority:** P2
**Classified:** not run (queued for the next triage)
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Prior art:** exact-slug glob, none; read `docs/bugs/2026-10-22-bug-tally-counts-implemented-and-deferred-as-open.md` (different root cause: status, not release)
**Waiting on:** operator decision — since 2026-11-15

## Symptom

Operator screenshot of the Bugs dashboard, 2026-11-15: nine open P2s listed under **v1.44.0**, including bugs the
2026-11-14 triage moved to v1.44.1 (`2026-11-13-stray-m4-air-repo-sync-group-on-hub-pushgateway.md`,
`2026-11-14-dev-machine-test-all-overwrites-nightly-suite-metrics.md`, `2026-11-14-dispatch-stall-a-detector.md`) and
to v1.45.0 plan 5 (`2026-11-14-dispatch-stall-b-approval.md`, `2026-11-14-dispatch-stall-c-diagnose.md`). v1.44.0
looks blocked by work that is not in it.

## Cause

`scripts/bug-tally.py:144-152` assigns a release with `doc_release` (`scripts/lib/hermes/prior_art.py:281`), which reads
only a `**Branch:** ... vX.Y.Z` line (`_BRANCH_RELEASE_RE`, `prior_art.py:119`) and otherwise falls back to the release
branch the doc was added on. Neither `**Triage:** patch → vX.Y.Z` / `carry → vX.Y.Z` (the triage record format
since 2026-11-14) nor `**Release:** vX.Y.Z` is read. `bin/k3dm-vectordb-metrics:665-686` takes that release for the
table's release label.

## Expected

A target named by the operator's triage decision or a `**Release:**` line wins over the filed-on release, so each
release's open count holds only bugs actually in it.
