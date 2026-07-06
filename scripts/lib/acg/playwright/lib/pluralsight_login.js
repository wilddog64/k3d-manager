'use strict';

const SIGNIN_URL = 'https://app.pluralsight.com/id/signin';
const SANDBOX_URL = 'https://app.pluralsight.com/hands-on/playground/cloud-sandboxes';
const EMAIL_SELECTOR = 'input[type="email"], input[name="username"], input[name="email"]';
const PASSWORD_SELECTOR = 'input[type="password"]';
const SUBMIT_SELECTOR = 'button[type="submit"], button:has-text("Sign in"), input[type="submit"]';
const LOGGED_IN_SELECTORS = [
  '[data-testid="user-menu"]',
  '[aria-label="User menu"]',
  '[aria-label*="account" i]',
  'img[alt*="avatar" i]',
  'text=/Cloud Sandboxes/i',
  'text=/Open Sandbox/i',
];
const MFA_SELECTORS = [
  'input[autocomplete="one-time-code"]',
  'text=/verification code/i',
  'text=/two-?factor/i',
  'text=/enter the code/i',
];

async function anyVisible(page, selectors, timeoutMs) {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if (await locator.isVisible({ timeout: timeoutMs }).catch(() => false)) {
      return true;
    }
  }
  return false;
}

async function pageLooksLoggedIn(page) {
  return anyVisible(page, LOGGED_IN_SELECTORS, 1500);
}

async function fillIfVisible(page, selector, value, timeoutMs) {
  const field = page.locator(selector).first();
  if (await field.isVisible({ timeout: timeoutMs }).catch(() => false)) {
    await field.click();
    await field.fill('');
    await field.fill(value);
    return true;
  }
  return false;
}

async function loginWithPage(page, username, password) {
  if (!username || !password) {
    return { ok: false, reason: 'no_creds' };
  }

  await page.goto(SIGNIN_URL, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});

  if (!page.url().includes('/id/signin') && await pageLooksLoggedIn(page)) {
    return { ok: true, reason: 'already_logged_in' };
  }

  await fillIfVisible(page, EMAIL_SELECTOR, username, 5000);
  await fillIfVisible(page, PASSWORD_SELECTOR, password, 5000);

  await page.locator(SUBMIT_SELECTOR).first().click();
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
  PASSWORD_SELECTOR,
  SANDBOX_URL,
  SIGNIN_URL,
  SUBMIT_SELECTOR,
  anyVisible,
  loginWithPage,
  pageLooksLoggedIn,
};
