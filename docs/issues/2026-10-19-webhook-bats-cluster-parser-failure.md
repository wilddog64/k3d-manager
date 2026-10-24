# Issue: webhook BATS suite has an unrelated cluster-parser failure

**Date:** 2026-10-19
**Status:** OPEN

## What was tested

The dispatched Slack Make-log lookup task ran the broader webhook BATS suite before the scoped landing gate. The implementation-specific tests passed, but the existing webhook suite failed at its cluster-parser test, which is outside the task scope.

## Actual output

```text
1..74
ok 1..24
not ok 25 Slack cluster parser accepts tokens in any order and dry-run isolates execution
# (in test file scripts/tests/lib/webhook.bats, line 474)
#   `[ "$status" -eq 0 ]' failed
ok 26..60
```

The scoped BATS suites passed separately:

```text
1..14
ok 1..14
```

## Root cause

Unknown. The failure is in the pre-existing Slack cluster parser behavior and is unrelated to recording the Make target marker for log selection.

## Recommended follow-up

Reproduce `scripts/tests/lib/webhook.bats` test 25 independently and determine why its dry-run parser status is non-zero. Do not fold that parser fix into the Slack Make-log lookup task.
