# CodeQL PR #161: `js/incomplete-url-substring-sanitization` in a test mock (false positive)

**Date:** 2026-11-15
**PR:** #161 (Release v1.44.0)
**Alerts:** 36, 37 — `scripts/lib/foundation/scripts/lib/acg/tests/providers/pluralsight_login.test.js:62` and `:153`
**Arrived with:** 79caba45 (subtree pull lib-foundation v0.5.6)
**Resolution:** dismissed as false positive

## Finding

CodeQL reports that `'challenges.cloudflare.com'` "can be anywhere in the URL, and arbitrary hosts may come before
or after it."

## Why it is a false positive

Both lines are Jest mocks of Playwright's `page.locator(selector)`. The string tested with `.includes()` is a CSS
selector the code under test passes in (the Cloudflare challenge iframe selector), not a URL from any source, and the
result only decides what count the fake locator returns. Nothing is sanitized, fetched or redirected. CodeQL's rule
matches any `.includes('<hostname>')`.

## Why not change the code

The file is in the lib-foundation subtree, which is edited upstream first and then pulled. Rewriting a test mock to
satisfy the rule would change no behaviour. If the rule fires again on production code under
`scripts/lib/acg/providers/`, that is a real finding and goes to lib-foundation.
