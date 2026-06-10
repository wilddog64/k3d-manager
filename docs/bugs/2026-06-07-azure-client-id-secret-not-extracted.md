# Bugfix: v0.1.4 — Azure provider doesn't extract Application Client ID and Secret

**Branch:** `feat/v0.1.4`
**Files:** `playwright/providers/azure.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

The Azure sandbox now shows two service principal credential fields — **Application Client ID**
and **Secret** — in addition to (or instead of) the existing username/password fields.
The current `azure.js` label detection only recognises `username|email`, `password`,
`subscription`, and `tenant`. Fields labelled "Application Client ID" and "Secret"
get no `fieldLabel` assigned and fall through to the positional fallback, which
incorrectly assigns them to `username` and `password` respectively.

The extracted env vars are wrong:
```
AZURE_USERNAME=ece905db-ee5f-4bd2-b39f-5a408fd56f79   # actually the client ID
AZURE_PASSWORD=Bsu8Q~npb75UeJ2WTZWpT2aDJOYWiDdMl     # actually the secret
```

They should be:
```
AZURE_CLIENT_ID=ece905db-ee5f-4bd2-b39f-5a408fd56f79
AZURE_CLIENT_SECRET=Bsu8Q~npb75UeJ2WTZWpT2aDJOYWiDdMl
```

**Root cause (lines 38–43):** the regex chain in the 6-ancestor label walk has no branch
for `/client/i` or `/\bsecret\b/i`, so those fields return `fieldLabel: null` and land
on the positional fallback at lines 64–67.

---

## Fix

### Change 1 — `playwright/providers/azure.js`: add `clientId` and `clientSecret` label branches

**Exact old block (lines 38–44 inside the `.map(inp => {` callback):**

```javascript
          if (!fieldLabel) {
            if (/username|email/i.test(t)) fieldLabel = 'username';
            else if (/password/i.test(t)) fieldLabel = 'password';
            else if (/subscription/i.test(t)) fieldLabel = 'subscription';
            else if (/tenant/i.test(t)) fieldLabel = 'tenant';
          }
```

**Exact new block (add `client` and `secret` checks BEFORE `password`):**

```javascript
          if (!fieldLabel) {
            if (/client/i.test(t)) fieldLabel = 'clientId';
            else if (/\bsecret\b/i.test(t)) fieldLabel = 'clientSecret';
            else if (/username|email/i.test(t)) fieldLabel = 'username';
            else if (/password/i.test(t)) fieldLabel = 'password';
            else if (/subscription/i.test(t)) fieldLabel = 'subscription';
            else if (/tenant/i.test(t)) fieldLabel = 'tenant';
          }
```

**Why this order:** `client` must precede `password` because some ancestor's `innerText`
may contain the word "password" from other fields in the same card. Matching the innermost
(most specific) label first avoids false positives. `secret` before `password` for the
same reason.

---

### Change 2 — `playwright/providers/azure.js`: declare and assign `clientId` / `clientSecret` variables

**Exact old block (lines 56–67):**

```javascript
  let username, password, subscriptionId, tenantId;
  for (const { value: val, fieldLabel } of azureInputs) {
    if (fieldLabel === 'username' && !username) username = val;
    else if (fieldLabel === 'password' && !password) password = val;
    else if (fieldLabel === 'subscription' && !subscriptionId) subscriptionId = val;
    else if (fieldLabel === 'tenant' && !tenantId) tenantId = val;
  }

  if (!username && azureInputs.length >= 1) username = azureInputs[0].value;
  if (!password && azureInputs.length >= 2) password = azureInputs[1].value;
  if (!subscriptionId && azureInputs.length >= 3) subscriptionId = azureInputs[2].value;
  if (!tenantId && azureInputs.length >= 4) tenantId = azureInputs[3].value;
```

**Exact new block:**

```javascript
  let username, password, subscriptionId, tenantId, clientId, clientSecret;
  for (const { value: val, fieldLabel } of azureInputs) {
    if (fieldLabel === 'clientId' && !clientId) clientId = val;
    else if (fieldLabel === 'clientSecret' && !clientSecret) clientSecret = val;
    else if (fieldLabel === 'username' && !username) username = val;
    else if (fieldLabel === 'password' && !password) password = val;
    else if (fieldLabel === 'subscription' && !subscriptionId) subscriptionId = val;
    else if (fieldLabel === 'tenant' && !tenantId) tenantId = val;
  }

  if (!username && azureInputs.length >= 1) username = azureInputs[0].value;
  if (!password && azureInputs.length >= 2) password = azureInputs[1].value;
  if (!subscriptionId && azureInputs.length >= 3) subscriptionId = azureInputs[2].value;
  if (!tenantId && azureInputs.length >= 4) tenantId = azureInputs[3].value;
```

---

### Change 3 — `playwright/providers/azure.js`: update error check and output block

**Exact old block (lines 69–79):**

```javascript
  if (!username || !password) {
    throw new Error('Could not find Azure Username and Password credentials');
  }

  const creds = {
    AZURE_USERNAME: username.trim(),
    AZURE_PASSWORD: password.trim(),
  };
  if (subscriptionId) creds.AZURE_SUBSCRIPTION_ID = subscriptionId.trim();
  if (tenantId) creds.AZURE_TENANT_ID = tenantId.trim();
  outputFn(creds);
```

**Exact new block:**

```javascript
  const hasUserPass = username && password;
  const hasServicePrincipal = clientId && clientSecret;
  if (!hasUserPass && !hasServicePrincipal) {
    throw new Error('Could not find Azure credentials (expected username+password or clientId+secret)');
  }

  const creds = {};
  if (username) creds.AZURE_USERNAME = username.trim();
  if (password) creds.AZURE_PASSWORD = password.trim();
  if (clientId) creds.AZURE_CLIENT_ID = clientId.trim();
  if (clientSecret) creds.AZURE_CLIENT_SECRET = clientSecret.trim();
  if (subscriptionId) creds.AZURE_SUBSCRIPTION_ID = subscriptionId.trim();
  if (tenantId) creds.AZURE_TENANT_ID = tenantId.trim();
  outputFn(creds);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/providers/azure.js` | Add `clientId`/`clientSecret` label branches; declare and assign new vars; update error check and output block |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/providers/azure.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `clientId` and `clientSecret` added to label detection regex chain, BEFORE `password`
- [ ] `let username, password, subscriptionId, tenantId, clientId, clientSecret;` declared
- [ ] `for` loop assigns `clientId` and `clientSecret` when label matches
- [ ] Error condition: throw if neither `(username && password)` nor `(clientId && clientSecret)` are set
- [ ] `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET` emitted conditionally in `creds`
- [ ] `node --check playwright/providers/azure.js` passes
- [ ] `make check lint test` passes (run in lib-acg repo root)
- [ ] `CHANGELOG.md` updated under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(azure): extract Application Client ID and Secret as AZURE_CLIENT_ID and AZURE_CLIENT_SECRET
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/providers/azure.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT touch `sandbox.js`, `acg_credentials.js`, `aws.js`, `gcp.js`, or any other file
- Do NOT remove the positional fallback — it is intentionally kept as a last resort for unknown field layouts
- Do NOT change `extractCredentials`'s function signature or the `waitForFunction` scoping block
