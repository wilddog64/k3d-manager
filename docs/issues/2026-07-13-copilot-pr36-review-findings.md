# Copilot PR #36 review findings — v0.4.4

**PR:** [#36](https://github.com/wilddog64/lib-foundation/pull/36) — `fix: v0.4.4 — ACG extend sandbox routing + js-yaml DoS advisory`
**Fix commit:** `7d52f30`
**Date:** 2026-07-13

---

## Finding 1 — `_isSandboxPageUrl` overly broad (`scripts/lib/acg/playwright/acg_extend.js:35`)

**Copilot:** `_isSandboxPageUrl` returned `true` for any URL containing `cloud-playground`
or `hands-on/playground`, even when the page is not the Cloud Sandboxes listing. That can
cause the script to skip navigation and then fail later when it can't find the Extend
controls — a variant of the stale-tab bug the extend fix was meant to close. Suggested
matching the specific sandbox path as in `playwright/lib/sandbox.js` (`.../cloud-sandboxes`).

**Before:**

```js
function _isSandboxPageUrl(url) {
  try {
    return url.includes('cloud-sandboxes') || url.includes('hands-on/playground') || url.includes('cloud-playground');
  } catch {
    return false;
  }
}
```

**After:**

```js
function _isSandboxPageUrl(url) {
  try {
    return url.includes('cloud-sandboxes');
  } catch {
    return false;
  }
}
```

**Root cause:** the OR-chain added `hands-on/playground` and `cloud-playground` as
independent matches to be permissive, but every real sandbox URL (listing
`cloud-playground/cloud-sandboxes` / `hands-on/playground/cloud-sandboxes`, and detail
subpaths `/cloud-sandboxes/<id>`) already contains `cloud-sandboxes`. The extra substrings
only matched generic, non-sandbox learning pages. Requiring `cloud-sandboxes` aligns with
`sandbox.js` (both `sandbox.js:11` and the `:471` subpath check) and still covers listing
+ subpaths.

## Finding 2 — missing negative regression assertion (`scripts/lib/acg/tests/providers/acg_extend.test.js:21`)

**Copilot:** the routing now hinges on distinguishing sandbox pages from other Pluralsight
pages; add a regression assertion for a non-sandbox `cloud-playground` page to keep
`_isSandboxPageUrl` from drifting broad again.

**Fix:** added a test asserting generic playground pages return `false` and a
`/cloud-sandboxes/<id>` subpath returns `true` (guards against over-tightening too):

```js
test('does not treat generic playground pages as sandbox pages', () => {
  expect(_isSandboxPageUrl('https://app.pluralsight.com/cloud-playground')).toBe(false);
  expect(_isSandboxPageUrl('https://app.pluralsight.com/hands-on/playground')).toBe(false);
  expect(
    _isSandboxPageUrl('https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/abc123')
  ).toBe(true);
});
```

**Gates:** `npm run check` clean; `npm test` → 6 suites / 19 tests pass (was 18).

---

## Process note

When a routing decision keys off a URL substring, match the **most specific** path segment
that uniquely identifies the target (here `cloud-sandboxes`), and pair it with a negative
test that pins a sibling non-target path to `false`. A permissive OR-chain of parent
segments (`cloud-playground`, `hands-on/playground`) re-opens the exact false-positive the
navigation guard exists to prevent.
