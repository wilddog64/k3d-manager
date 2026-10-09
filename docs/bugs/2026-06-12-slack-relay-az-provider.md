# Bugfix: Slack relay still uses `azure` — `/acg-up az` provisions AWS, not Azure

**Status:** CLOSED — doc merged to main in PR #94; no open follow-up was found. Not individually re-verified; reopen with a Recurrence section if it is seen again (2026-10-09 status sweep)
**Date:** 2026-06-12
**Branch:** `k3d-manager-v1.6.5`
**Files:** `workers/slack-relay/index.js`

---

## Problem

From Slack, `/acg-up az` provisions an **AWS** cluster (`make up CLUSTER_PROVIDER=k3s-aws`)
instead of Azure. Confirmed via job `584302f2`: output line 1 is
`Running make up CLUSTER_PROVIDER=k3s-aws...` and the job dir carries a `hooks.slack.com`
`response_url` (slash-command path), not an Events-API message.

**Root cause:** the `k3s-azure → k3s-az` rename (commit `46d9b360`) updated `bin/k3dm-webhook`
(now validates `provider in ("aws","gcp","az")`) but **missed the Cloudflare relay**
`workers/slack-relay/index.js`, which still uses the old `azure` token:

```js
const VALID_PROVIDERS = new Set(['aws', 'gcp', 'azure'])   // line 2
...
const provider = VALID_PROVIDERS.has(text) ? text : 'aws'  // line 89 (/acg-up), line 121 (/acg-resume)
```

Double mismatch, both ending in `aws`:
- `/acg-up az` → `text="az"` → `VALID_PROVIDERS.has("az")` is **false** (set only has `azure`) → `provider="aws"`.
- `/acg-up azure` → relay forwards `provider="azure"` → webhook rejects it (only accepts `az`) → `provider="aws"`.

Same defect on `/acg-resume`.

---

## Reproduction

```
# In Slack:
/acg-up az
# → bot posts "🚀 acg-up (aws) started" and runs make up CLUSTER_PROVIDER=k3s-aws
```

---

## Fix

Update the relay to the canonical `az` token and accept `azure` as a friendly alias that
normalizes to `az` (so both `/acg-up az` and `/acg-up azure` work). Two call sites
(`/acg-up`, `/acg-resume`) read the provider — both must normalize.

### Change 1 — `workers/slack-relay/index.js` line 2 (provider set + alias map)

**Exact old block:**
```js
const VALID_PROVIDERS   = new Set(['aws', 'gcp', 'azure'])
```

**Exact new block:**
```js
const VALID_PROVIDERS   = new Set(['aws', 'gcp', 'az'])
const PROVIDER_ALIASES  = { azure: 'az' }
```

### Change 2 — `/acg-up` handler (normalize before validating)

**Exact old block:**
```js
  if (command === '/acg-up') {
    const provider = VALID_PROVIDERS.has(text) ? text : 'aws'
```

**Exact new block:**
```js
  if (command === '/acg-up') {
    const _p = PROVIDER_ALIASES[text] || text
    const provider = VALID_PROVIDERS.has(_p) ? _p : 'aws'
```

### Change 3 — `/acg-resume` handler (normalize before validating)

**Exact old block:**
```js
  if (command === '/acg-resume') {
    const provider = VALID_PROVIDERS.has(text) ? text : 'aws'
```

**Exact new block:**
```js
  if (command === '/acg-resume') {
    const _p = PROVIDER_ALIASES[text] || text
    const provider = VALID_PROVIDERS.has(_p) ? _p : 'aws'
```

> Note: lines 89 and 121 are byte-identical, so each block above includes its `if (command === ...)`
> line to disambiguate the match. Do NOT use a global replace.

---

## Files Changed

| File | Change |
|------|--------|
| `workers/slack-relay/index.js` | `VALID_PROVIDERS` `azure`→`az`; add `PROVIDER_ALIASES = { azure: 'az' }`; normalize provider in `/acg-up` and `/acg-resume` |

---

## Rules

- `node --check workers/slack-relay/index.js` — passes
- Dry verify the normalization: confirm `az` → `az`, `azure` → `az`, `aws`/`gcp` unchanged, garbage → `aws`
- No file other than `workers/slack-relay/index.js` touched
- Do NOT touch `bin/k3dm-webhook` (its `("aws","gcp","az")` set is already correct)

---

## Definition of Done

- [ ] 3 edits applied (set+alias, `/acg-up` normalize, `/acg-resume` normalize)
- [ ] `node --check workers/slack-relay/index.js` passes
- [ ] Dry-run check: `az`→`az`, `azure`→`az`, `aws`→`aws`, `gcp`→`gcp`, `foo`→`aws`
- [ ] Committed and pushed to `k3d-manager-v1.6.5`
- [ ] memory-bank updated with commit SHA and task status

**After verify (operator step — note in completion report):** redeploy the worker so Slack
picks up the change — `cd workers/slack-relay && npx --yes wrangler deploy` (requires Cloudflare
auth; analogous to `make restart-webhook` for the local webhook).

**Commit message (exact):**
```
fix(slack-relay): accept az provider (+ azure alias) for /acg-up and /acg-resume
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `workers/slack-relay/index.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.5`
- Do NOT run `wrangler deploy` as part of the commit — deploy is a separate operator step after verify
