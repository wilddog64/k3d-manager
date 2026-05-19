# Copilot PR #77 Review Findings

**PR:** #77 — fix(acg): vault temp file leaks, CDP hang, Keycloak frontendUrl, Cloudflare tunnel
**Date:** 2026-05-19

---

## Finding 1 — CHANGELOG.md:6: Wrong vault.sh path

**File:** `CHANGELOG.md` line 6
**Flagged:** Entry referenced `scripts/lib/vault.sh`; changes are in `scripts/plugins/vault.sh`

**Fix:** Corrected path in CHANGELOG `[Unreleased]` section.

```diff
-`scripts/lib/vault.sh`: register cleanup traps immediately after mktemp...
+`scripts/plugins/vault.sh`: register cleanup traps immediately after mktemp...
```

**Root cause:** Copilot agent wrote the wrong subdirectory when generating the CHANGELOG entry.

**Process note:** CHANGELOG entries for plugin changes must use `scripts/plugins/` not `scripts/lib/`.

---

## Finding 2 — acg_credentials.js:111: GCP positional field extraction fragile

**File:** `scripts/lib/acg/playwright/acg_credentials.js` line 111
**Flagged:** GCP credentials extracted by positional index (inputs[0], inputs[1], inputs[2]); if both AWS and GCP panels are visible, positional extraction can pick up AWS values.
**Status:** Pre-existing code — not introduced or modified by PR #77.

**Root cause:** GCP credential fields share the same `aria-label="Copyable input"` as AWS fields. Positional extraction works when the GCP panel is isolated but is fragile when multiple providers are visible.

**Follow-on:** Write a bug spec in `docs/bugs/` — validate that `inputs[2]` starts with `{` (JSON) as a content guard before treating it as the service account JSON field.

---

## Finding 3 — acg_extend.js:129: Navigation skip too broad

**File:** `scripts/lib/acg/playwright/acg_extend.js` line 129
**Flagged:** Any `*.pluralsight.com` hostname is treated as "already on Pluralsight" and skips navigation; this includes the home page and login pages which don't have the extend UI.
**Status:** Pre-existing code — not introduced or modified by PR #77 (PR only changed the `finally` block).

**Root cause:** The check was added to avoid unnecessary navigation when the correct sandbox page is already open, but it doesn't verify the sandbox URL path is correct.

**Follow-on:** Write a bug spec — add a check that the current URL contains the expected sandbox path before skipping navigation.

---

## Finding 4 — acg_credentials.js:452: `.first()` can open wrong provider sandbox

**File:** `scripts/lib/acg/playwright/acg_credentials.js` around line 452
**Flagged:** `startButton2.first()` picks the first "Start Sandbox" button on the page, which may belong to the AWS card rather than the GCP card when `--provider gcp` is passed.
**Status:** Pre-existing code — not introduced or modified by PR #77.

**Root cause:** Provider-specific button selection uses `.first()` rather than scoping within the card matching the requested provider.

**Follow-on:** Write a bug spec — scope button locator to the card element that matches the provider argument.
