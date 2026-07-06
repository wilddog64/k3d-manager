#!/usr/bin/env node
'use strict';

const { chromium } = require('playwright');
const {
  SANDBOX_URL,
  SIGNIN_URL,
  loginWithPage,
  pageLooksLoggedIn,
} = require('./playwright/lib/pluralsight_login');

const CDP_HOST = process.env.PLAYWRIGHT_CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.PLAYWRIGHT_CDP_PORT || '9222';
const CDP_URL = `http://${CDP_HOST}:${CDP_PORT}`;
const POLL_INTERVAL_MS = 5000;
const LOGIN_TIMEOUT_MS = 300000;

async function _autoLogin(browser) {
  if (!process.env.ACG_USERNAME || !process.env.ACG_PASSWORD) {
    return false;
  }

  const context = browser.contexts()[0];
  if (!context) {
    throw new Error('No browser context found via CDP');
  }

  const page = context.pages()[0] || await context.newPage();
  const result = await loginWithPage(page, process.env.ACG_USERNAME, process.env.ACG_PASSWORD);
  if (result.reason === 'mfa_required') {
    console.error('ACG_LOGIN_MFA_REQUIRED: MFA challenge detected — unsupported for unattended login');
  }
  return result.ok;
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
    if (await pageLooksLoggedIn(page)) {
      process.stdout.write('ACG_SESSION_OK\n');
      return;
    }

    if (process.env.ACG_USERNAME && process.env.ACG_PASSWORD) {
      console.error('INFO: Session not authenticated — attempting headless Pluralsight login...');
      const loginOk = await _autoLogin(browser).catch(err => {
        console.error(`INFO: auto-login error: ${err.message}`);
        return false;
      });
      if (loginOk && await pageLooksLoggedIn(page)) {
        process.stdout.write('ACG_SESSION_OK\n');
        return;
      }
      console.error('INFO: headless auto-login did not succeed.');
    }

    if (process.env.K3DM_NONINTERACTIVE === '1' || !process.stdout.isTTY) {
      console.error(`ACG_SESSION_EXPIRED: Pluralsight session not authenticated and auto-login unavailable — sign in on the host CDP Chrome (${CDP_URL}) and re-run.`);
      throw new Error('ACG_SESSION_EXPIRED');
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
      if (!page.url().includes('/signin') && await pageLooksLoggedIn(page)) {
        process.stdout.write('ACG_SESSION_OK\n');
        return;
      }
      await page.waitForTimeout(POLL_INTERVAL_MS);
    }

    throw new Error('Pluralsight login timeout');
  } finally {
    await browser.close().catch(() => {});
  }
}

if (require.main === module) {
  _main().catch(err => {
    console.error(`ERROR: ${err.message}`);
    process.exit(1);
  });
}

module.exports = {
  LOGIN_TIMEOUT_MS,
  POLL_INTERVAL_MS,
  _autoLogin,
  _main,
};
