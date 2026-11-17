# Bug: the bug tables put every triaged bug in the release it was filed on, ignoring `**Triage:**` and `**Release:**`

**Status:** LIVE-VERIFIED — 2026-11-17, E3 by Claude on the dashboard data source (ledger live_verified 8cff0301). Was: VERIFIED — 2026-11-16, independent offline verifier (claude) passed, recorded in the dispatch ledger; live check pending. Was: LANDED — 8cff0301 on k3d-manager-v1.44.1, 2026-11-16 (Luna; Claude verified: 8 tests red pre-fix, 140 green; corpus diff 179 docs, ~25 move to their groomed release, rest same release from an explicit line)
**Live evidence:** 2026-11-17 · run hub-prometheus-k3dm_bug_info-v1.44.1 · env hub/k3d-k3d-cluster · scenario bugs-dashboard-release-v1.44.1-lists-triaged-bugs · commit 6fe58dcb · proves E3
**Fix commit:** 8cff0301
**Priority:** P2
**Classified:** not run (queued for the next triage)
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Prior art:** exact-slug glob, none; read `docs/bugs/2026-10-22-bug-tally-counts-implemented-and-deferred-as-open.md` (different root cause: status, not release)
**Branch:** k3d-manager-v1.44.1
**Triage:** patch → v1.44.1 — operator 2026-11-16 ("yes", pulled in from carry → v1.45.0 because the dashboard cannot show v1.44.1 progress without it)

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

## Fix

Precedence in `doc_release` (`scripts/lib/hermes/prior_art.py:281`), first match wins:

1. `**Triage:** carry → vX.Y.Z` or `**Triage:** patch → vX.Y.Z` — the value must start with `carry` or `patch`, then
   `→` (or `->`), then the version; source `triage_line`. Any other Triage value (`passed over`, `close`,
   `status corrected`) is not a release and falls through.
2. `**Release:** vX.Y.Z` — the value must start with the version; source `release_line`. Free-form values
   (`P3 batch`, `deferred …`, `TBD`, `carried to v1.44.0 unless …`) fall through.
3. `**Branch:** … vX.Y.Z` — unchanged, source `branch_line`.
4. The added-on release, unchanged.

`scripts/bug-tally.py:143` skips the git-history lookup for every doc whose release is explicit: replace
`!= "branch_line"` with a check against the three explicit sources. `:152` is unchanged: for other repos only a
`branch_line` is ignored, because their branch names do not carry a k3d-manager version, while a Triage or Release line
does.

## Files

- `scripts/lib/hermes/prior_art.py`
- `scripts/bug-tally.py`
- `scripts/tests/bin/test_prior_art.py`
- `scripts/tests/bin/test_bug_tally.py`

## Contract readers

- `scripts/lib/hermes/prior_art.py:281` — writer of `(release, source)`; gains sources `triage_line`, `release_line`.
- `scripts/bug-tally.py:143` — reader; explicit-source check widened (see Fix).
- `scripts/bug-tally.py:150-152` — reader; unchanged.
- `scripts/bug-tally.py:158,229` — `by_source` counts and the text report print the source names; new names appear,
  nothing parses them.
- `bin/k3dm-vectordb-metrics:665-686` — reader of the tally's per-release path lists; unchanged, it takes whatever
  release the tally assigns.
- `grep -rn "doc_release\|branch_line" scripts bin` (2026-11-16) finds no other reader.

## Acceptance

```yaml
must:
  - id: M1
    text: a doc whose Triage line is "carry → vX.Y.Z" or "patch → vX.Y.Z" (or "->") is tallied under vX.Y.Z with source triage_line, even when it also has a Branch line naming another release
  - id: M2
    text: a doc whose Release line starts with vX.Y.Z is tallied under vX.Y.Z with source release_line when it has no carry/patch Triage line
  - id: M3
    text: Triage values that are not carry/patch (passed over, close, status corrected) and free-form Release values (P3 batch, deferred, TBD, "carried to v1.44.0 unless …") do not set a release; the Branch line or added-on release still applies
  - id: M4
    text: a doc with a triage_line or release_line release does not trigger the git log lookup in counts-only mode
  - id: M5
    text: existing Branch-line and added-on behaviour is unchanged (existing test_doc_release_uses_branch_or_added_release and test_bug_tally.py stay green)
must_not:
  - id: N1
    text: a doc added on v1.44.0 with "**Triage:** carry → v1.45.0" is tallied under v1.44.0 — red today
  - id: N2
    text: a doc with "**Branch:** k3d-manager-v1.44.0" and "**Triage:** patch → v1.44.1" is tallied under v1.44.0 — red today
evidence:
  - id: E1
    proves: [M1, M2, M3, M5, N1, N2]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_prior_art.py -q
    intent: A bug moved to another release at grooming is counted in that release, and ordinary notes in those lines are ignored.
  - id: E2
    proves: [M4, N1]
    kind: offline
    command: python3 -m pytest scripts/tests/bin/test_bug_tally.py -q
    intent: The bug tally groups bugs by their groomed release without slowing down.
  - id: E3
    proves: [M1]
    kind: live
    command: after hub-promote and the next bug-metrics run, the Bugs dashboard with Release=v1.44.1 lists the ten groomed v1.44.1 bugs (operator)
    intent: The dashboard shows this release's own bugs under this release.
interface: none
```

**Intent approved:** operator, 2026-11-16

## Live verification 2026-11-17 (Claude)

E3 PASS on the Bugs dashboard's data source, read-only on the M5 hub Prometheus: `k3dm_bug_current_release_info` is v1.44.1 and `k3dm_bug_info{release="v1.44.1"}` has 17 rows (12 fixed, 5 open P3s captured on the branch). Every groomed v1.44.1 bug is listed, including those filed under earlier releases and moved by `Triage:`/`Release:` lines (containment 2026-11-12, stray Pushgateway 2026-11-13, Hermes ci 2026-11-13), which the pre-fix code put under their filing release. The operator may still glance at the Grafana panel; the data it renders is proven here. Evidence: `<run>/live-evidence.txt`.
