# `codex-dispatch open --count` counts a review child whose role was set by `link`

**Status:** OPEN
**Priority:** P3
**Introduced by:** 6972d10a (multi-project M1: `open --count`)
**Should have been caught by:** spec
**Introducing change reviewed:** no
**Waiting on:** operator decision
**Prior art:** not run (vector store unreachable; exact-slug glob found none)

## Report

On 2026-11-17 Claude started `dirused-m2b-review` with `start` and then ran `link --parent dirused-m2b-top-folders --role review`.
After that, `open --count` printed `dirused 1/3`. The run is a review child, so the WIP rule says it should not count.

The open-count reader (`bin/k3dm-codex-dispatch:1592`) takes `role` only from the first `start` event. The `link` event,
which carries the role, is never read. M1's test P7 passes `--role` on `start`, so this path was never exercised.

## Impact

The count overstates a project's WIP by one for each review linked after it starts, so a dispatch may be held back when a
slot is actually free. Claude counts WIP by hand from `open` (review children excluded), so no dispatch has been blocked.

## Fix sketch

Take the role from the latest `start` or `link` event that has one. Test: a task started with no role and then linked with
`--role review` is not counted; a task linked with `--role build` is counted (the positive control).
