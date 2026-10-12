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
const GCP_PASSWORD = process.env.GCP_PASSWORD || '';
const GCP_AUTH_URL = process.env.GCP_AUTH_URL || '';

async function handleGcpOAuthFlow() {
  const browser = await chromium.connectOverCDP(CDP_URL);
  const contexts = browser.contexts();
  if (contexts.length === 0) {
    throw new Error('No browser context found via CDP');
  }
  const context = contexts[0];

  // Dismiss "Sign in to Chrome?" dialog — Chrome offers to sync with the signed-in Google
  // account; appears as a new page mid-OAuth flow. Dismiss without creating a Chrome profile.
  context.on('page', async (page) => {
    try {
      await page.waitForLoadState('domcontentloaded', { timeout: 5000 }).catch(() => {});
      const noChromeSignInBtn = page.locator('button:has-text("Use Chrome Without an Account")');
      if (await noChromeSignInBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        console.error('INFO: Dismissing "Sign in to Chrome?" dialog...');
        await noChromeSignInBtn.click();
      }
    } catch { /* best-effort */ }
  });

  // Step 0 — Navigate to Google logout to clear all stale sessions
  console.error('INFO: Clearing stale Google sessions...');
  const logoutPage = await context.newPage();
  await logoutPage.goto('https://accounts.google.com/Logout', { waitUntil: 'domcontentloaded', timeout: 15000 });
  await logoutPage.close();

  let oauthPage;
  if (GCP_AUTH_URL) {
    // Linux headless: gcloud cannot open a browser — navigate to the URL it printed
    console.error('INFO: Navigating directly to gcloud OAuth URL (Linux headless)...');
    oauthPage = await context.newPage();
    await oauthPage.goto(GCP_AUTH_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  } else {
    // No URL provided: wait for gcloud to open the OAuth tab directly in this CDP session
    oauthPage = context.pages().find(p => {
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
  }
  console.error(`INFO: OAuth tab found: ${oauthPage.url()}`);

  await oauthPage.waitForLoadState('domcontentloaded', { timeout: 15000 });

  // Step 1 — Use another account (force fresh credential entry after logout)
  const useAnotherAccountBtn = oauthPage.locator(
    'li:has-text("Use another account"), div:has-text("Use another account")'
  ).first();
  if (await useAnotherAccountBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Clicking "Use another account"...');
    await useAnotherAccountBtn.click();
    await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
  }

  // Step 1b — Enter email
  if (GCP_ACCOUNT) {
    const emailInput = oauthPage.locator('input[type="email"]').first();
    if (await emailInput.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.error('INFO: Entering email...');
      await emailInput.fill(GCP_ACCOUNT);
      await oauthPage.locator('button:has-text("Next")').first().click();
      await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
    }
  }

  // Step 1c — Enter password
  const gcpPassword = process.env.GCP_PASSWORD || '';
  if (gcpPassword) {
    const passwordInput = oauthPage.locator('input[type="password"]').first();
    if (await passwordInput.isVisible({ timeout: 10000 }).catch(() => false)) {
      console.error('INFO: Entering password...');
      await passwordInput.fill(gcpPassword);
      await oauthPage.locator('button:has-text("Next")').first().click();
      await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
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
