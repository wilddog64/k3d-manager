# Bug: `/ask-docs` bug counts ignore "last two releases" and dump every release unsorted

**Filed:** 2026-10-10
**Branch:** `k3d-manager-v1.43.0`
**Status:** FIXED 2026-10-10 (Claude, in-tree; see CHANGELOG [1.43.0])
**Priority:** P3 — the counts were correct, the answer was unreadable
**Severity:** low

## Symptom

`/ask-docs how many P1 bugs from last two releases` answered with every release since v1.1.0: a
line per release, most of them `0 P1 bug docs`, each followed by its own "N docs have no Priority
line" note. The releases came in tally order, not version order (v1.4.7 before v1.4.6, v1.27.0
between v1.8.0 and v1.10.0), and the reply ran off the Slack screen.

## Cause

`scripts/lib/webhook/bug_count.py` only recognised a literal version (`v1.42.0`). Any other range,
"last two releases", "this release", fell through to `release="*"`, which printed every key of
`bug-tally --json` in dict order, with no filter on zero rows and no cap.

## Fix

- `match()` understands `last|past|previous|recent N releases` (digits or one–ten) and
  `this|current|latest release` (= last 1). An explicit version still wins.
- "Last N" counts back from the current release branch (`K3DM_INDEX_REF`, or the checked-out
  branch for `HEAD`), so releases scheduled later (`v1.44.0`, `v1.43.2` from `Branch:` lines) are
  not counted as recent. The reply names the releases it chose.
- All-release answers are sorted newest version first, start with a total, skip releases with
  no match and show at most ten, saying how many were left out.
- The missing-Priority note appears once, summed over the selection.

## Tests

`scripts/tests/bin/test_bug_count.py`: four new `match` cases, plus last-N selection (current
and earlier only, one Priority note), version order with the ten-release cap, and zero-row
skipping. Six of the new tests fail on the old code; replacing the version sort with tally order
fails two.

## Follow-up

The router is still regex. Count questions phrased another way ("bugs we closed since August")
fall through to similarity search. See the discussion of a small grammar vs a model-produced
query object in `memory-bank/activeContext.md` (2026-10-10).
