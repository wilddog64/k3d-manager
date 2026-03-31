# Issue: acg_extend Playwright Script Fails — Extend Button Not Found

**Date:** 2026-03-31
**Milestone:** v1.0.2
**Severity:** Medium — TTL extension fails silently; sandbox expires during long sessions

---

## Symptom

Gemini's static Playwright script (`ag_acg_extend.js`) exits with code 1:

```
Searching for extend button...
Error: Extend button not found or not visible.
```

The script uses `page.getByRole('button', { name: /Extend|\+4 hours/i })` which fails
to match the actual button rendered on the Pluralsight sandbox page.

---

## Root Cause

The selector assumes the Extend button:
- Has an ARIA role of `button`
- Has visible text matching `/Extend|\+4 hours/i`
- Is visible immediately after `domcontentloaded`

In practice the button may be:
- Inside a modal or slide-over panel that requires a prior click to open
- Behind a loading/skeleton state (`aria-busy="true"`) that hasn't cleared
- Rendered with different text (e.g. "Add 4 hours", "Extend Sandbox", "Renew")
- Not present at all if the sandbox is in a non-extendable state

The existing `antigravity_acg_extend` function avoids this by using a freeform
Gemini CLI prompt, which adapts to whatever the page looks like at runtime.
A static script with hardcoded selectors is inherently brittle for this UI.

---

## Impact

- `acg_watch` calls `antigravity_acg_extend` on a timer — if the static script path
  is used instead, the sandbox TTL will not be extended automatically
- Sandbox expires mid-session → credentials invalidated → tunnel drops → Gemini tasks fail
- Observed during v1.0.2 Gemini e2e run (2026-03-31)

---

## Proposed Fix

**Short term:** use `antigravity_acg_extend` (freeform Gemini CLI) — do not replace it
with a static Playwright script. The freeform approach is more robust for UI that changes.

**Proper fix (v1.0.3 candidate):** if a static script is desired, model it after
`acg_credentials.js` with:
1. Wait for `aria-busy` to clear before searching for buttons
2. Multiple selector fallbacks: `button:has-text("Extend")`, `button:has-text("Add 4 hours")`,
   `button:has-text("Renew")`, `[data-testid*="extend"]`
3. Try opening a panel/modal first if no button found at top level
4. Non-fatal timeout with a clear error message rather than `process.exit(1)`

---

## Related

- `docs/issues/2026-03-31-pluralsight-session-expiry-independent-of-sandbox-ttl.md`
- `scripts/plugins/antigravity.sh` — `antigravity_acg_extend` (working freeform approach)
- `acg_watch` — calls `antigravity_acg_extend` on a 3.5h timer
