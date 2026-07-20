#!/usr/bin/env node
'use strict';

const { chromium } = require('playwright');
const {
  SANDBOX_URL,
  loginWithPage,
} = require('./lib/pluralsight_login');

const CDP_HOST = process.env.PLAYWRIGHT_CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.PLAYWRIGHT_CDP_PORT || '9222';
const CDP_URL = `http://${CDP_HOST}:${CDP_PORT}`;
const USERNAME = process.env.ACG_USERNAME || '';
const PASSWORD = process.env.ACG_PASSWORD || '';

async function _main() {
  if (!USERNAME || !PASSWORD) {
    console.error('ACG_LOGIN_NO_CREDS: ACG_USERNAME/ACG_PASSWORD not set');
    process.exit(3);
  }

  const browser = await chromium.connectOverCDP(CDP_URL);
  try {
    const contexts = browser.contexts();
    if (contexts.length === 0) {
      throw new Error('No browser context found via CDP');
    }

    const context = contexts[0];
    const page = context.pages()[0] || await context.newPage();
    const result = await loginWithPage(page, USERNAME, PASSWORD);

    if (result.ok) {
      process.stdout.write('ACG_SESSION_OK\n');
      return;
    }

    if (result.reason === 'mfa_required') {
      console.error('ACG_LOGIN_MFA_REQUIRED: MFA challenge detected — this flow supports only no-MFA accounts');
      process.exit(4);
    }

    if (result.reason === 'no_creds') {
      console.error('ACG_LOGIN_NO_CREDS: ACG_USERNAME/ACG_PASSWORD not set');
      process.exit(3);
    }

    await page.goto(SANDBOX_URL, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});
    console.error('ACG_LOGIN_FAILED: sign-in did not reach an authenticated sandbox page');
    process.exit(1);
  } finally {
    await browser.close().catch(() => {});
  }
}

if (require.main === module) {
  _main().catch(err => {
    console.error(`ACG_LOGIN_FAILED: ${err.message}`);
    process.exit(1);
  });
}

module.exports = {
  _main,
};
