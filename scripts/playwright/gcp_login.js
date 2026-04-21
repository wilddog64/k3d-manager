'use strict';

const { chromium } = require('playwright');

/**
 * scripts/playwright/gcp_login.js
 *
 * Automates the Google OAuth consent flow triggered by `gcloud auth login`.
 * Connects to the running Chrome CDP session and handles:
 *   1. "Choose an account" — selects the account matching GCP_ACCOUNT arg
 *   2. "Managed Profile" confirmation — clicks Continue / Got it
 *   3. Terms of Service — clicks I agree / Accept
 *   4. OAuth scopes — clicks Allow
 *
 * Usage:
 *   node gcp_login.js <gcp-account-email>
 *
 * Environment:
 *   PLAYWRIGHT_CDP_HOST  (default: 127.0.0.1)
 *   PLAYWRIGHT_CDP_PORT  (default: 9222)
 */

const CDP_HOST = process.env.PLAYWRIGHT_CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.PLAYWRIGHT_CDP_PORT || '9222';
const CDP_URL = `http://${CDP_HOST}:${CDP_PORT}`;
const GCP_ACCOUNT = process.argv[2] || process.env.GCP_USERNAME || '';

async function handleGcpOAuthFlow() {
  const browser = await chromium.connectOverCDP(CDP_URL);
  const contexts = browser.contexts();
  if (contexts.length === 0) {
    throw new Error('No browser context found via CDP');
  }
  const context = contexts[0];

  // Check if the OAuth tab is already open before waiting for a new one
  let oauthPage = context.pages().find(p => {
    try {
      const h = new URL(p.url()).hostname;
      return h === 'accounts.google.com' || h.endsWith('.google.com');
    } catch { return false; }
  });

  if (!oauthPage) {
    console.error('INFO: Waiting for Google OAuth tab (up to 30s)...');
    oauthPage = await context.waitForEvent('page', {
      predicate: p => {
        try {
          const h = new URL(p.url()).hostname;
          return h === 'accounts.google.com' || h.endsWith('.google.com');
        } catch { return false; }
      },
      timeout: 30000
    });
  }
  console.error(`INFO: OAuth tab found: ${oauthPage.url()}`);

  await oauthPage.waitForLoadState('domcontentloaded', { timeout: 15000 });

  // Step 1 — Choose account
  if (GCP_ACCOUNT) {
    const accountLink = oauthPage.locator(
      `[data-email="${GCP_ACCOUNT}"], div[data-identifier="${GCP_ACCOUNT}"]`
    ).first();
    if (await accountLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.error(`INFO: Selecting account ${GCP_ACCOUNT}...`);
      await accountLink.click();
      await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
    } else {
      // Fallback: click the first listed account
      const firstAccount = oauthPage.locator('div[data-identifier], li.JDAKTe').first();
      if (await firstAccount.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking first listed account (fallback)...');
        await firstAccount.click();
        await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
      }
    }
  }

  // Step 2 — Managed Profile confirmation (shown for Google Workspace accounts)
  const managedProfileBtn = oauthPage.locator(
    'button:has-text("Got it"), button:has-text("Continue"), button:has-text("I understand"), button:has-text("Confirm")'
  ).first();
  if (await managedProfileBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Confirming Managed Profile...');
    await managedProfileBtn.click();
    await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
  }

  // Step 3 — Terms of Service
  const tosBtn = oauthPage.locator(
    'button:has-text("I agree"), button:has-text("Accept"), button:has-text("Agree and continue")'
  ).first();
  if (await tosBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Accepting Terms of Service...');
    await tosBtn.click();
    await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
  }

  // Step 4 — Allow gcloud OAuth scopes
  const allowBtn = oauthPage.locator('button:has-text("Allow")').first();
  if (await allowBtn.isVisible({ timeout: 15000 }).catch(() => false)) {
    console.error('INFO: Clicking Allow...');
    await allowBtn.click();
  } else {
    console.error('WARN: Allow button not found — OAuth may have completed via redirect');
  }

  // Wait for gcloud callback (localhost redirect signals completion)
  await oauthPage.waitForURL('*localhost*', { timeout: 30000 }).catch(() => {
    console.error('INFO: No localhost redirect observed — assuming OAuth completed');
  });
  console.error('INFO: GCP OAuth flow complete.');

  try { await browser.disconnect(); } catch {}
}

const TIMEOUT_MS = 60000;
let _timeoutHandle;
const _timeoutPromise = new Promise((_, reject) => {
  _timeoutHandle = setTimeout(
    () => reject(new Error(`gcp_login.js timed out after ${TIMEOUT_MS / 1000}s`)),
    TIMEOUT_MS
  );
});

Promise.race([handleGcpOAuthFlow(), _timeoutPromise])
  .then(() => {
    clearTimeout(_timeoutHandle);
    process.exit(0);
  })
  .catch(err => {
    clearTimeout(_timeoutHandle);
    console.error(`ERROR: ${err.message}`);
    process.exit(1);
  });
