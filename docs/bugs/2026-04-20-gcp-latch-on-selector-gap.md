# Bug Fix: add missing ToS and Profile selectors to gcp_login.js

**Branch:** `k3d-manager-v1.1.0`
**File:** `scripts/playwright/gcp_login.js`

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/playwright/gcp_login.js` in full (lines 80–98 are the two affected steps)

---

## Problem

`gcp_login.js` Step 2 (Managed Profile) and Step 3 (Terms of Service) miss button variants
shown on fresh ACG sandboxes:

- Step 2 currently matches: `"Got it"`, `"Continue"`, `"I understand"`
  — Missing: **`"Confirm"`** (Chrome profile data handling dialog)
- Step 3 currently matches: `"I agree"`, `"Accept"`
  — Missing: **`"Agree and continue"`** (GCP ToS variant for fresh accounts)

Result: the robot hangs and `gcp_login` times out after 60s on first-use sandboxes.

---

## Fix

**Change 1 — Step 2 locator (line 82):**

```js
// current
  const managedProfileBtn = oauthPage.locator(
    'button:has-text("Got it"), button:has-text("Continue"), button:has-text("I understand")'
  ).first();
```

```js
// replacement
  const managedProfileBtn = oauthPage.locator(
    'button:has-text("Got it"), button:has-text("Continue"), button:has-text("I understand"), button:has-text("Confirm")'
  ).first();
```

**Change 2 — Step 3 locator (line 92):**

```js
// current
  const tosBtn = oauthPage.locator(
    'button:has-text("I agree"), button:has-text("Accept")'
  ).first();
```

```js
// replacement
  const tosBtn = oauthPage.locator(
    'button:has-text("I agree"), button:has-text("Accept"), button:has-text("Agree and continue")'
  ).first();
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/playwright/gcp_login.js` | Line 82: add `"Confirm"` selector; line 92: add `"Agree and continue"` selector |

---

## Rules

- Only `scripts/playwright/gcp_login.js` may be touched
- Do NOT change any logic, timeouts, or other steps — selector strings only

---

## E2E Verification

### Test S1 — confirm new selectors present
```bash
grep -n "Confirm" scripts/playwright/gcp_login.js
grep -n "Agree and continue" scripts/playwright/gcp_login.js
```
Expected: one match each at the lines modified above.

### Test S2 — node syntax check
```bash
node --check scripts/playwright/gcp_login.js && echo "syntax OK"
```
Expected: `syntax OK`.

### Test S3 — live E2E (run with active GCP sandbox on fresh session)
```bash
source scripts/plugins/gcp.sh
gcp_get_credentials
```
Expected: completes without timeout; `gcloud auth list` shows cloud_user as ACTIVE.

---

## Definition of Done

- [ ] `scripts/playwright/gcp_login.js` line 82: includes `button:has-text("Confirm")`
- [ ] `scripts/playwright/gcp_login.js` line 92: includes `button:has-text("Agree and continue")`
- [ ] Tests S1–S2 pass — paste actual outputs
- [ ] Test S3 — live smoke test run and result pasted (or noted as sandbox unavailable)
- [ ] Committed and pushed to `k3d-manager-v1.1.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(gcp): add missing ToS and Profile selectors to gcp_login.js
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/playwright/gcp_login.js`
- Do NOT commit to `main`
- Do NOT change timeouts, logic flow, or other selector strings
