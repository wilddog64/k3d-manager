# Issue — "Extend Your Session" dialog blocks `acg_credentials.js` nav-link click

## What happened

`acg-up` failed at the credential extraction step after a sandbox restart with:

```
ERROR: locator.click: Timeout 30000ms exceeded.
Call log:
  - waiting for locator('a[href*="cloud-sandboxes"]').first()
    - locator resolved to <a ... href="/hands-on/playground/cloud-sandboxes" ...>Cloud Sandboxes</a>
  - attempting click action
    ...
    - <dialog open="" role="alertdialog" aria-atomic="true" data-testid="extend-sandbox-modal" ...>
        intercepts pointer events
    - retrying click action
      ...
ERROR: Credential extraction after restart failed.
make: *** [up] Error 1
```

## Root cause

The Pluralsight SPA fires an "Extend Your Session" modal (`data-testid="extend-sandbox-modal"`,
`role="alertdialog"`) when the sandbox is nearing its shutdown time. This modal is rendered as a
`<dialog open>` element with pointer-event capture over the full viewport.

The SPA nav branch in `extractCredentials()` called `_dismissExtendYourSessionDialog()` then
`navLink.click()`. Because the dismiss is asynchronous and React re-triggers the dialog on a timer,
the dialog could reappear between the dismiss call and the click — causing `navLink.click()` to spin
retrying for 30 s before timing out.

## Fix

Replace `navLink.click()` with `page.evaluate(url => window.location.assign(url), targetUrl)`.
JS-driven navigation is not subject to pointer-event interception, so the modal cannot block it.
The `navVisible` check and the `_dismissExtendYourSessionDialog()` pre-call are also removed as
they are no longer needed in this branch.

**File:** `playwright/acg_credentials.js` — SPA-nav branch (~line 361)

**Branch:** `fix/next-improvements-8`

## Verification

Run `make up` with an ACG sandbox that has been running long enough to trigger the extend-session
prompt. The nav step should complete without timeout and credentials should be extracted normally.
