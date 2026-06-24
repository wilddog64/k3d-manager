#!/usr/bin/env node
'use strict';

const { chromium } = require('playwright');

const CDP_HOST = process.env.PLAYWRIGHT_CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.PLAYWRIGHT_CDP_PORT || '9222';
const CDP_URL = `http://${CDP_HOST}:${CDP_PORT}`;
const SANDBOX_URL = 'https://app.pluralsight.com/hands-on/playground/cloud-sandboxes';
const SIGNIN_URL = 'https://app.pluralsight.com/id/signin';
const POLL_INTERVAL_MS = 5000;
const LOGIN_TIMEOUT_MS = 300000;

const LOGIN_SELECTORS = [
  '[data-testid="user-menu"]',
  '[aria-label="User menu"]',
  '[aria-label*="account" i]',
  'img[alt*="avatar" i]',
  'text=/Cloud Sandboxes/i',
];

async function _pageLooksLoggedIn(page) {
  for (const selector of LOGIN_SELECTORS) {
    const locator = page.locator(selector).first();
    if (await locator.isVisible({ timeout: 1500 }).catch(() => false)) {
      return true;
    }
  }
  return false;
}

async function _main() {
  const browser = await chromium.connectOverCDP(CDP_URL);
  try {
    const contexts = browser.contexts();
    if (contexts.length === 0) {
      throw new Error('No browser context found via CDP');
    }

    const context = contexts[0];
    const pages = context.pages();
    const page = pages.length > 0 ? pages[0] : await context.newPage();

    await page.goto(SANDBOX_URL, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});
    if (await _pageLooksLoggedIn(page)) {
      process.stdout.write('ACG_SESSION_OK\n');
      return;
    }

    console.error('ACTION REQUIRED: Please log into Pluralsight in the browser, then wait for the signin page to clear.');
    const reachedSignin = await page.goto(SIGNIN_URL, { waitUntil: 'domcontentloaded', timeout: 30000 })
      .then(() => true)
      .catch(() => false);
    if (!reachedSignin) {
      throw new Error('Failed to navigate to Pluralsight signin page');
    }

    const deadline = Date.now() + LOGIN_TIMEOUT_MS;
    while (Date.now() < deadline) {
      if (!page.url().includes('/signin') && await _pageLooksLoggedIn(page)) {
        process.stdout.write('ACG_SESSION_OK\n');
        return;
      }
      await page.waitForTimeout(POLL_INTERVAL_MS);
    }

    throw new Error('Pluralsight login timeout');
  } finally {
    try {
      await browser.disconnect();
    } catch {}
  }
}

_main().catch(err => {
  console.error(`ERROR: ${err.message}`);
  process.exit(1);
});
