'use strict';
const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');

const AUTH_DIR = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'playwright-auth');

async function run() {
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  let url, username, password;
  try {
    ({ url, username, password } = JSON.parse(input));
  } catch {
    console.error('ERROR: stdin must be JSON with url, username, password');
    process.exit(1);
  }
  if (!url || !username || !password) {
    console.error('ERROR: url, username, and password are required');
    process.exit(1);
  }

  let browserContext = null;
  let _cdpBrowser = null;

  try {
    // Try CDP first (reuse existing Chrome session)
    try {
      _cdpBrowser = await chromium.connectOverCDP('http://localhost:9222');
      const ctxs = _cdpBrowser.contexts();
      if (ctxs.length > 0) {
        browserContext = ctxs[0];
        console.error('INFO: Reusing existing Chrome session via CDP');
      } else {
        await _cdpBrowser.close();
        _cdpBrowser = null;
      }
    } catch {
      _cdpBrowser = null;
    }

    if (!browserContext) {
      browserContext = await chromium.launchPersistentContext(AUTH_DIR, {
        headless: false,
        channel: 'chrome',
        args: ['--password-store=basic'],
      });
      console.error('INFO: Launched new Chrome persistent context');
    }

    const page = browserContext.pages()[0] || await browserContext.newPage();
    console.error(`INFO: Navigating to auth URL...`);
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });

    // Account chooser — pick cloud_user or enter via "Use another account"
    const accountChooser = page.locator('div[data-identifier]').filter({ hasText: username });
    const chooserVisible = await accountChooser.first().isVisible({ timeout: 5000 }).catch(() => false);
    if (chooserVisible) {
      console.error(`INFO: Selecting existing account ${username}`);
      await accountChooser.first().click();
    } else {
      const useAnother = page.getByText('Use another account', { exact: true }).first();
      const useAnotherVisible = await useAnother.isVisible({ timeout: 5000 }).catch(() => false);
      if (useAnotherVisible) {
        console.error(`INFO: URL before click: ${page.url()}`);
        console.error('INFO: Clicking "Use another account"');
        await useAnother.click();
        await page.waitForTimeout(1000);
        console.error(`INFO: URL after click: ${page.url()}`);
      }
      // Fill email — SPA transition; wait directly for input
      const emailInput = page.locator('input[type="email"], input#identifierId').first();
      await emailInput.waitFor({ timeout: 30000 });
      await emailInput.fill(username);
      console.error(`INFO: Filled email ${username}`);
      const nextBtn = page.locator('button:has-text("Next")').first();
      await nextBtn.click();
    }

    // Password — optional: persistent context may already have an active session
    const passwordInput = page.locator('input[type="password"]').first();
    const passwordVisible = await passwordInput.isVisible({ timeout: 5000 }).catch(() => false);
    if (passwordVisible) {
      await passwordInput.fill(password);
      console.error('INFO: Filled password');
      const passNext = page.locator('button:has-text("Next")').first();
      await passNext.click();
      await page.waitForTimeout(500);
      console.error(`INFO: URL after password Next: ${page.url()}`);
    } else {
      console.error('INFO: Password step skipped — session already authenticated');
      console.error(`INFO: URL (no password): ${page.url()}`);
    }

    // "I understand" — may appear twice (new account welcome)
    for (let i = 0; i < 2; i++) {
      const iUnderstand = page.locator('button:has-text("I understand"), input[value="I understand"]').first();
      const visible = await iUnderstand.isVisible({ timeout: 5000 }).catch(() => false);
      if (visible) {
        console.error(`INFO: Clicking "I understand" (${i + 1})`);
        await iUnderstand.click();
        await page.waitForTimeout(1000);
      }
    }

    // "Skip" / "Not now" — Google phone/recovery prompts on new accounts
    for (const label of ['Skip', 'Not now', 'Confirm']) {
      const btn = page.getByRole('button', { name: label }).first();
      const visible = await btn.isVisible({ timeout: 3000 }).catch(() => false);
      if (visible) {
        console.error(`INFO: Clicking "${label}"`);
        await btn.click();
        await page.waitForTimeout(500);
      }
    }

    // "Continue" (Sign in to Google Cloud SDK confirmation)
    const continueBtn = page.locator('button:has-text("Continue")').first();
    const continueVisible = await continueBtn.isVisible({ timeout: 10000 }).catch(() => false);
    if (continueVisible) {
      console.error('INFO: Clicking "Continue"');
      await continueBtn.click();
    }

    // "Allow" (Google Cloud SDK access grant)
    console.error(`INFO: URL before Allow: ${page.url()}`);
    
    // Log all visible button texts for diagnosis
    const allBtns = await page.locator('button').all();
    for (const b of allBtns) {
      const txt = await b.textContent().catch(() => '');
      const vis = await b.isVisible().catch(() => false);
      if (vis && txt.trim()) console.error(`INFO: visible button: "${txt.trim()}"`);
    }

    // Second account chooser — signin/oauth/id shows an inline account picker
    // before the Allow button when authuser=0 (active session) is set
    const secondChooser = page.locator('div[data-identifier]').filter({ hasText: username });
    const secondChooserVisible = await secondChooser.first().isVisible({ timeout: 5000 }).catch(() => false);
    if (secondChooserVisible) {
      console.error(`INFO: Second account chooser detected — clicking ${username}`);
      await secondChooser.first().click();
      await page.waitForTimeout(1000);
      console.error(`INFO: URL after second chooser: ${page.url()}`);
    }

    // Try Allow variants — Google sometimes uses different labels
    const allowBtn = page.locator(
      'button:has-text("Allow"), button:has-text("Grant access"), button:has-text("Yes, I\'m in")'
    ).first();
    try {
      await allowBtn.waitFor({ timeout: 30000 });
    } catch (e) {
      // Dump page text for diagnosis before failing
      const bodyText = await page.textContent('body').catch(() => '');
      console.error(`INFO: page body on Allow timeout:\n${bodyText.substring(0, 2000)}`);
      throw e;
    }
    console.error('INFO: Clicking "Allow"');
    await allowBtn.click();

    // Extract the one-time auth code from the final page
    await page.waitForTimeout(2000);
    const codeInput = page.locator('input[readonly], textarea[readonly], code').first();
    const codeVisible = await codeInput.isVisible({ timeout: 10000 }).catch(() => false);
    let authCode = '';
    if (codeVisible) {
      authCode = await codeInput.inputValue().catch(() => '') || await codeInput.textContent().catch(() => '');
    }
    if (!authCode) {
      // Fallback: look for the code in page text
      const bodyText = await page.textContent('body').catch(() => '');
      const match = bodyText.match(/4\/[A-Za-z0-9_\-]+/);
      if (match) authCode = match[0];
    }
    if (!authCode) {
      console.error('ERROR: Could not extract auth code from final page');
      process.exit(1);
    }

    console.error('INFO: Auth code extracted');
    console.log(authCode.trim());

  } finally {
    if (_cdpBrowser) {
      try { await _cdpBrowser.close(); } catch {}
    } else if (browserContext) {
      await browserContext.close();
    }
  }
}

run().catch(err => {
  console.error(`ERROR: ${err.message}`);
  process.exit(1);
});
