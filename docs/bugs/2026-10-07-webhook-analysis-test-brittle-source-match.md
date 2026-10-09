# Webhook analysis regression test breaks on normal Python formatting

**Filed:** 2026-10-07
**Release / branch:** v1.42.0 / `k3d-manager-v1.42.0`
**Status:** FIXED
**Severity:** Low — the implementation is correct, but the full test target reports a false failure
**Component:** `scripts/tests/lib/webhook.bats`

## Observed behavior

The webhook test run reported:

```text
not ok 379 webhook analysis uses ordered candidates and a safe sentinel
# (in test file scripts/tests/lib/webhook.bats, line 600)
#   `[ "$status" -eq 0 ]' failed
```

The test used a fixed-string grep for the complete one-line expression
`os.environ.get("K3DM_AI_BIN_ORDER", "agy,gemini")`. The production code contains the same
expression split across adjacent Python source lines, so the grep returned status 1 even though
the ordered-candidate behavior was present.

## Root cause

The regression test asserted incidental source formatting instead of the expression's syntax.
Normal line wrapping or formatting changes could therefore turn a passing implementation into a
false test failure.

## Fix

Replace the fixed-string source check with a small Python syntax-shape check that allows
whitespace between the call's tokens while retaining the existing safe-sentinel assertion.

## Acceptance

- [x] The test recognizes the ordered-candidate environment lookup across normal line wrapping.
- [x] The safe sentinel remains asserted.
- [x] The focused webhook test passes.
- [x] The full BATS suite and required audit/lint checks pass.
