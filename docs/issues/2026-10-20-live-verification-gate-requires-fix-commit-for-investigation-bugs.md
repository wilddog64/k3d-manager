# LIVE-VERIFIED evidence gate blocks incident-cause investigations without a fix commit

**Date:** 2026-10-20
**Area:** Bug evidence validation
**Related bug:** `docs/bugs/2026-10-17-hostinger-node-unresponsive-then-rebooted.md`

## What was attempted

Recorded operator-provided Hostinger support evidence that attributes the VPS shutdown to
platform-initiated emergency security-patch maintenance, and attempted to promote the
investigation bug from `VERIFIED` to `LIVE-VERIFIED`.

## Actual output

```text
check-doc-links: 3 file(s) OK
docs/bugs/2026-10-17-hostinger-node-unresponsive-then-rebooted.md: LIVE-VERIFIED requires a well-formed **Live evidence:** line
Pre-commit hook: newly LIVE-VERIFIED bug docs need a well-formed Live evidence line
  format: **Live evidence:** YYYY-MM-DD · run <id> · env <value> · scenario <value> · commit <sha> · proves <ids>
  guide:   docs/guides/grafana-dashboards.md
  bypass:  K3DM_SKIP_BUG_EVIDENCE=1 git commit ...
ERROR: Checkpoint commit failed; resolve git errors and retry
```

The required live-evidence tuple is designed to prove a software fix commit. The incident
investigation has no software fix commit; its live evidence is a provider control-plane review.
Assigning the offline report commit as a “fix” would misrepresent what that commit did. The hook
was not bypassed.

## Root cause

`scripts/check-bug-evidence.py` requires every newly `LIVE-VERIFIED` bug document to include a
`**Fix commit:**` and a `**Live evidence:**` line whose evidence commit contains that fix commit.
There is no supported evidence shape for provider-confirmed incident cause or other investigation
bugs with no code fix.

## Resolution

Added a distinct `**Verification type:** investigation` and typed
`**Live investigation evidence:**` format for provider/audit-confirmed investigations with no
software fix commit. The gate rejects malformed evidence, missing investigation typing, and use
of this path on a bug that declares a fix commit. Existing code-fix verification still requires
the original `**Fix commit:**` and ancestry-checked `**Live evidence:**` format. Regression tests
cover both the new path and its boundaries.
