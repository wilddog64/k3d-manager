# Bug: e2e Keycloak token request is labelled JSON, so Keycloak sees no `grant_type`

**Filed:** 2026-10-02
**Status:** OPEN
**Repo:** `wilddog64/shopping-cart-e2e-tests`
**Branch (work repo):** `fix/keycloak-token-form-content-type`, from `origin/main` (`755ad2d`)
**File:** `tests/helpers/auth.ts` (`mintToken`)
**Related:** `docs/bugs/2026-09-16-e2e-assertion-api-payments.md` (option (b), real Keycloak token)

## Symptom

Live Tier 1 run `1790965743-22494` (image `sha-755ad2d7efeb96dcb6d3701077264fc6b9374db3`): 48 passed,
8 failed, 102 total. All 8 failures are in `api/payments.spec.ts`, and each one fails in the token step:

```
Error: Keycloak token request failed: 400 {"error":"invalid_request","error_description":"Missing form parameter: grant_type"}
```

## Root cause

`playwright.config.ts` sets a header on every request:

```ts
    extraHTTPHeaders: {
      'X-User-ID': process.env.TEST_USER_ID || 'e2e-test-user',
      'Content-Type': 'application/json',
    },
```

`mintToken` posts with `form:`. The body Playwright sends is URL-encoded, but the global `Content-Type`
header still says `application/json`. Keycloak's token endpoint parses the body according to that
header, finds no form fields, and returns `Missing form parameter: grant_type`.

A header set on the request itself takes precedence over `extraHTTPHeaders`, so the fix is to name the
form content type on this one request. The global header stays as it is, because the JSON API calls
depend on it.

## Fix (`tests/helpers/auth.ts`)

Old:
```ts
  const response = await request.post(tokenUrl, {
    form: {
```
New:
```ts
  const response = await request.post(tokenUrl, {
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    form: {
```

## Gate (paste output)

1. **Proof script, not committed.** Write it under `$TMPDIR` or a scratch dir outside the repo.
   - Start a local `http.createServer` on `127.0.0.1:0` that records `req.headers['content-type']` and the raw
     body.
   - Create `request.newContext({ extraHTTPHeaders: { 'Content-Type': 'application/json' } })` from
     `@playwright/test`. No browser is needed.
   - Post to the server twice with `form: { grant_type: 'password' }`:
     - **(a)** with no `headers`. Expected: content-type `application/json`, which reproduces the bug.
     - **(b)** with the fix's `headers`. Expected: content-type `application/x-www-form-urlencoded` and a body
       containing `grant_type=password`.
   - Print both results.
2. `npx tsc --noEmit` error count must equal `origin/main`'s count, which was 11 when last measured. Report
   both counts.
3. `npm run lint` must report no new errors in `tests/helpers/auth.ts`.

## Definition of Done

- [ ] Fix applied exactly as written; no other file changed
- [ ] Gates 1–3 output pasted
- [ ] Commit message: `fix(auth): send the Keycloak token request as a form, not JSON`
- [ ] Pushed to `origin/fix/keycloak-token-form-content-type`; report `git rev-parse origin/fix/keycloak-token-form-content-type`

## What NOT to Do

- Do NOT create a PR. Claude prepares it, and the operator approves.
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT change `playwright.config.ts`. The JSON API calls depend on the global header.
- Do NOT modify files other than `tests/helpers/auth.ts`
- Do NOT commit to `main`
- Do NOT run `make e2e` or any live test
