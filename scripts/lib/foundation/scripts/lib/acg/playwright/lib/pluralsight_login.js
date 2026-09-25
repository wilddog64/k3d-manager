'use strict';

const SIGNIN_URL = 'https://app.pluralsight.com/id/signin';
const SANDBOX_URL = 'https://app.pluralsight.com/hands-on/playground/cloud-sandboxes';
// Pluralsight's identity form uses PascalCase attributes (name="Username", id="Username") on a
// type="text" input. CSS attribute VALUES are case-sensitive, so a lowercase [name="username"]
// arm matches nothing -- measured live: the old selector returned count=0 while the form was
// fully rendered and visible. Keep the " i" flag on every name/id arm.
const EMAIL_SELECTOR = 'input[type="email"], input[name="username" i], input[name="email" i], input[id="username" i]';
const PASSWORD_SELECTOR = 'input[type="password"]';
const SUBMIT_SELECTOR = 'button[type="submit"], button:has-text("Sign in"), input[type="submit"]';
const FIELD_TIMEOUT_MS = 15000;
const LOGGED_IN_SELECTORS = [
  '[data-testid="user-menu"]',
  '[aria-label="User menu"]',
  '[aria-label*="account" i]',
  'img[alt*="avatar" i]',
  '.psPrismAvatar .psPrismMonogram[aria-label]',
];

const SIGNED_OUT_SELECTORS = [
  'a[href*="/id/signin"]',
  'button:has-text("Sign in")',
  'a:has-text("Sign in")',
];
const MFA_SELECTORS = [
  'input[autocomplete="one-time-code"]',
  'text=/verification code/i',
  'text=/two-?factor/i',
  'text=/enter the code/i',
];

// The Pluralsight identity SPA drops Playwright's synthetic click (force:true skips
// actionability but still issues the click the SPA ignores, and does not waive the
// viewport requirement). Drive submit with a dispatched DOM MouseEvent instead.
// evaluate() would otherwise fall back to Playwright's 30s default budget while the rest of
// this module waits on FIELD_TIMEOUT_MS. Wait explicitly so a never-rendered submit button
// fails on this module's own budget.
async function _robustClick(locator, timeoutMs = FIELD_TIMEOUT_MS) {
  await locator.waitFor({ state: 'visible', timeout: timeoutMs });
  await locator.evaluate(el => {
    el.scrollIntoView({ block: 'center', inline: 'center' });
    el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
  });
}

async function anyVisible(page, selectors, timeoutMs) {
  const checks = selectors.map((selector) =>
    page.locator(selector).first().isVisible({ timeout: timeoutMs }).catch(() => false),
  );
  if (checks.length === 0) {
    return false;
  }
  return new Promise((resolve) => {
    let pending = checks.length;
    for (const check of checks) {
      check.then((visible) => {
        if (visible) {
          resolve(true);
        } else if ((pending -= 1) === 0) {
          resolve(false);
        }
      });
    }
  });
}

function urlLooksSignedOut(url) {
  return typeof url === 'string' && /^https:\/\/app\.pluralsight\.com\/id(\/|$|\?)/.test(url);
}

async function pageLooksSignedOut(page, timeoutMs = 1500) {
  if (urlLooksSignedOut(page.url())) {
    return true;
  }
  return anyVisible(page, SIGNED_OUT_SELECTORS, timeoutMs);
}

async function pageLooksLoggedIn(page, options) {
  const { attempts = 1, perSelectorTimeoutMs = 1500, settleMs = 1000 } = options || {};
  for (let i = 0; i < attempts; i += 1) {
    if (await pageLooksSignedOut(page, perSelectorTimeoutMs)) {
      return false;
    }
    if (await anyVisible(page, LOGGED_IN_SELECTORS, perSelectorTimeoutMs)) {
      return true;
    }
    if (i < attempts - 1) {
      await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
      await page.waitForTimeout(settleMs);
    }
  }
  return false;
}

async function fillIfVisible(page, selector, value, timeoutMs) {
  const field = page.locator(selector).first();
  try {
    await field.waitFor({ state: 'visible', timeout: timeoutMs });
  } catch {
    return false;
  }
  await field.fill('');
  await field.fill(value);
  return true;
}

async function loginWithPage(page, username, password) {
  if (!username || !password) {
    return { ok: false, reason: 'no_creds' };
  }

  await page.goto(SIGNIN_URL, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});

  if (!page.url().includes('/id/signin') && await pageLooksLoggedIn(page)) {
    return { ok: true, reason: 'already_logged_in' };
  }

  const emailFilled = await fillIfVisible(page, EMAIL_SELECTOR, username, FIELD_TIMEOUT_MS);
  const passwordFilled = await fillIfVisible(page, PASSWORD_SELECTOR, password, FIELD_TIMEOUT_MS);

  if (!emailFilled || !passwordFilled) {
    console.error(`ACG_LOGIN_FIELDS_MISSING: email=${emailFilled ? 'filled' : 'missing'} password=${passwordFilled ? 'filled' : 'missing'}`);
    return { ok: false, reason: 'login_form_unavailable' };
  }

  await _robustClick(page.locator(SUBMIT_SELECTOR).first());
  await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(2000);

  if (await anyVisible(page, MFA_SELECTORS, 3000)) {
    return { ok: false, reason: 'mfa_required' };
  }

  await page.goto(SANDBOX_URL, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(2000);

  if (!page.url().includes('/id/signin') && await pageLooksLoggedIn(page)) {
    return { ok: true, reason: 'authenticated' };
  }

  return { ok: false, reason: 'login_failed' };
}

module.exports = {
  EMAIL_SELECTOR,
  LOGGED_IN_SELECTORS,
  MFA_SELECTORS,
  _robustClick,
  PASSWORD_SELECTOR,
  SANDBOX_URL,
  SIGNED_OUT_SELECTORS,
  SIGNIN_URL,
  SUBMIT_SELECTOR,
  anyVisible,
  loginWithPage,
  pageLooksLoggedIn,
  pageLooksSignedOut,
  urlLooksSignedOut,
};
