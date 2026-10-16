# lib-foundation Playwright test-results permission hiccup

## What I tested

- `make test`
- `cd scripts/lib/acg && npx playwright test --config playwright.config.js`

## Actual output

```text
Error: EPERM: operation not permitted, mkdir '/Users/cliang/src/gitrepo/personal/lib-foundation/scripts/lib/acg/test-results'
```

## Root cause

The first Playwright run tried to create its default `test-results/` directory inside the repository path, but the sandbox did not allow that write. The test run itself was valid; the failure was environment-specific.

## Follow-up

- Re-ran the same Playwright command with elevated workspace access and confirmed the 7-test suite passes.
- Consider documenting a writable output directory override for sandboxed verification runs if this keeps recurring.
