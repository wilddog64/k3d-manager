const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');

/**
 * scripts/playwright/acg_credentials.js
 *
 * Static Playwright script to extract AWS credentials from Pluralsight Cloud Sandbox.
 * Launches a persistent Chrome context — session persists across runs via auth dir.
 * Auth dir: ~/.local/share/k3d-manager/playwright-auth
 */

const AUTH_DIR = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'playwright-auth');

function _isFirstRun() {
  try {
    return !fs.existsSync(AUTH_DIR) || fs.readdirSync(AUTH_DIR).length === 0;
  } catch {
    return true;
  }
}
const IS_FIRST_RUN = _isFirstRun();

async function extractCredentials() {
  const targetUrl = process.argv[2];
  if (!targetUrl) {
    console.error('ERROR: No target URL provided');
    process.exit(1);
  }

  if (IS_FIRST_RUN) {
    console.error('BOOTSTRAP: Auth dir is empty — first run detected.');
    console.error(`BOOTSTRAP: Auth dir: ${AUTH_DIR}`);
    console.error('BOOTSTRAP: Chrome will open. Please log in to Pluralsight when prompted.');
    console.error('BOOTSTRAP: The script will continue automatically after successful login (up to 300s).');
  }

  let browserContext;
  let _cdpBrowser = null;
  try {
    if (IS_FIRST_RUN) {
      try {
        _cdpBrowser = await chromium.connectOverCDP('http://localhost:9222');
        const _cdpContexts = _cdpBrowser.contexts();
        if (_cdpContexts.length > 0) {
          const _cdpContext = _cdpContexts[0];
          const _cdpPages = _cdpContext.pages();
          const _cdpPsPage = _cdpPages.find(p => {
            try { return new URL(p.url()).hostname.endsWith('.pluralsight.com'); } catch { return false; }
          });
          if (_cdpPsPage) {
            console.error('INFO: Found existing Pluralsight session via CDP — reusing existing Chrome instance.');
            browserContext = _cdpContext;
          }
        }
        if (!browserContext) {
          await _cdpBrowser.disconnect();
          _cdpBrowser = null;
        }
      } catch {
        _cdpBrowser = null;
      }
    }
    if (!browserContext) {
      browserContext = await chromium.launchPersistentContext(AUTH_DIR, {
        headless: false,
        channel: 'chrome',
        args: ['--password-store=basic'],
      });
    }

    // 2. Find the Pluralsight page by URL (do not assume pages()[0])
    const context = browserContext;
    if (!context) throw new Error('No browser context found');
    const allPages = context.pages();
    let page = allPages.find(p => {
      try { return new URL(p.url()).hostname.endsWith('.pluralsight.com') || new URL(p.url()).hostname === 'pluralsight.com'; } catch { return false; }
    });
    if (!page) {
      page = allPages[0];
      if (!page) throw new Error('No page found in the browser context');
    }

    // Navigate only if not already on the target URL (hard reload kills SPA auth)
    const currentUrl = page.url();
    let currentHostname = '';
    try { currentHostname = new URL(currentUrl).hostname; } catch { /* non-URL, will navigate */ }
    let targetPathname = '';
    try { targetPathname = new URL(targetUrl).pathname; } catch { /* invalid targetUrl */ }
    let currentPathname = '';
    try { currentPathname = new URL(currentUrl).pathname; } catch { /* non-URL */ }

    if (currentHostname !== 'app.pluralsight.com') {
      console.error(`INFO: Navigating to ${targetUrl}...`);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    } else if (currentPathname === targetPathname) {
      console.error(`INFO: Already on ${currentUrl} — skipping navigation`);
    } else if (targetPathname.includes('cloud-sandboxes')) {
      console.error(`INFO: SPA-navigating to cloud-sandboxes from ${currentUrl}...`);
      const navLink = page.locator('a[href*="cloud-sandboxes"]').first();
      const navVisible = await navLink.isVisible({ timeout: 5000 }).catch(() => false);
      if (navVisible) {
        await navLink.click();
      } else {
        await page.evaluate(url => window.location.assign(url), targetUrl);
      }
    } else {
      console.error(`INFO: Navigating to ${targetUrl}...`);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    }

    // Give it time to render SPA content after navigation changes
    console.error('INFO: Waiting for page content to load...');
    await page.waitForFunction(
      () => !document.querySelector('[aria-busy="true"]'),
      { timeout: 30000 }
    ).catch(() => console.error('WARN: Skeleton loaders did not clear within 30s — proceeding anyway'));

    // 2b. Handle unauthenticated state — sign in via Google Password Manager if needed
    const signInLink = page.locator('a[href*="id.pluralsight.com"], a:has-text("Sign In"), button:has-text("Sign In")').first();
    const isSignInVisible = await signInLink.isVisible({ timeout: 10000 }).catch(() => false);
    if (isSignInVisible) {
      console.error('INFO: Not signed in — clicking Sign In...');
      await signInLink.click();
      await page.waitForURL('**id.pluralsight.com**', { timeout: 30000 })
        .catch(() => console.error('WARN: Did not reach id.pluralsight.com — proceeding anyway'));

      // Fill email field — set PLURALSIGHT_EMAIL env var to assist Google Password Manager
      const emailInput = page.locator('input[type="email"], input[name="email"], input[id*="email"]').first();
      await emailInput.waitFor({ timeout: 30000 });
      await emailInput.click();
      const email = process.env.PLURALSIGHT_EMAIL || '';
      if (email) {
        await emailInput.fill(email);
        console.error('INFO: Filled email from PLURALSIGHT_EMAIL');
      } else {
        console.error('INFO: Clicked email field — waiting for Google Password Manager auto-fill (set PLURALSIGHT_EMAIL to assist)');
        await page.waitForTimeout(5000);
      }

      // Click Continue if the form uses a two-step email-then-password flow
      const continueBtn = page.locator('button[type="submit"], button:has-text("Continue")').first();
      if (await continueBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
        await continueBtn.click();
        await page.waitForTimeout(3000);
      }

      // Wait for password field and let Google Password Manager auto-fill it
      const passwordInput = page.locator('input[type="password"]').first();
      if (await passwordInput.isVisible({ timeout: 10000 }).catch(() => false)) {
        await passwordInput.click();
        await page.waitForTimeout(5000); // allow Password Manager to populate
        const submitBtn = page.locator('button[type="submit"], button:has-text("Sign in"), button:has-text("Log in")').first();
        if (await submitBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
          await submitBtn.click();
          console.error('INFO: Submitted sign-in form — waiting for redirect...');
        }
      }

      // Wait for redirect back to Pluralsight after successful auth
      await page.waitForURL('**app.pluralsight.com**', { timeout: 300000 });
      console.error('INFO: Sign-in complete — resuming credential extraction...');

      // Re-wait for SPA content to settle after auth redirect
      await page.waitForFunction(
        () => !document.querySelector('[aria-busy="true"]'),
        { timeout: 30000 }
      ).catch(() => console.error('WARN: Skeleton loaders did not clear after login — proceeding anyway'));
    }

    // 3. Handle Sandbox Start/Open Flow
    // Skip only if credentials are already populated (not just visible — inputs render empty before start)
    const _firstCredInput = page.locator('input[aria-label="Copyable input"]').first();
    const _firstCredVisible = await _firstCredInput.isVisible({ timeout: 3000 }).catch(() => false);
    const _firstCredValue = _firstCredVisible ? await _firstCredInput.inputValue().catch(() => '') : '';
    const credentialsAlreadyVisible = _firstCredVisible && _firstCredValue.trim().length > 0;
    if (credentialsAlreadyVisible) {
      console.error('INFO: Credentials already populated — skipping Start/Open flow');
    } else {
      console.error('INFO: Looking for Start/Open button...');

      const _waitForCredentials = async () => {
        console.error('INFO: Waiting for credentials to populate (up to 60s)...');
        await page.waitForFunction(
          () => {
            const inputs = document.querySelectorAll('input[aria-label="Copyable input"]');
            return inputs.length > 0 && inputs[0].value.trim().length > 0;
          },
          { timeout: 60000 }
        );
      };

      // Pattern 1: Direct "Start Sandbox" button (in a modal or panel)
      const startButton = page.locator('button:has-text("Start Sandbox")').first();
      // Pattern 2: "Open Sandbox" button (on the card)
      const openButton = page.locator('button:has-text("Open Sandbox")').first();
      // Pattern 3: "Resume Sandbox"
      const resumeButton = page.locator('button:has-text("Resume"), button:has-text("Resume Sandbox")').first();

      if (await startButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Start Sandbox...');
        await startButton.click();
        await _waitForCredentials();
      } else if (await openButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Open Sandbox...');
        await openButton.click();
        await page.waitForTimeout(3000);

        // After Open, there might be a Start Sandbox button in the slide-over
        const startButton2 = page.locator('button:has-text("Start Sandbox")').first();
        if (await startButton2.isVisible({ timeout: 5000 }).catch(() => false)) {
          console.error('INFO: Clicking Start Sandbox (Step 2)...');
          await startButton2.click();
        }
        await _waitForCredentials();
      } else if (await resumeButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Resume Sandbox...');
        await resumeButton.click();
        await _waitForCredentials();
      }
    }

    // 4. Extract credentials
    console.error('INFO: Extracting credentials...');
    
    // We found that credentials are in inputs with aria-label="Copyable input"
    // The order is typically: Username, Password, Access Key ID, Secret Access Key, [Session Token]
    
    // Wait for the inputs to appear
    await page.waitForSelector('input[aria-label="Copyable input"]', { timeout: 15000 });
    
    const inputs = await page.locator('input[aria-label="Copyable input"]').all();
    console.error(`INFO: Found ${inputs.length} copyable inputs.`);

    let accessKey, secretKey, sessionToken;

    for (let i = 0; i < inputs.length; i++) {
      const val = await inputs[i].inputValue();
      const parent = await inputs[i].evaluateHandle(el => el.closest('div')?.parentElement ?? null);
      const text = parent ? await parent.evaluate(el => el.innerText || '') : '';
      
      if (text.toLowerCase().includes('access key id')) {
        accessKey = val;
      } else if (text.toLowerCase().includes('secret access key')) {
        secretKey = val;
      } else if (text.toLowerCase().includes('session token')) {
        sessionToken = val;
      }
    }

    // Fallback based on known order if text matching fails
    if (!accessKey && inputs.length >= 3) {
      accessKey = await inputs[2].inputValue();
    }
    if (!secretKey && inputs.length >= 4) {
      secretKey = await inputs[3].inputValue();
    }
    if (!sessionToken && inputs.length >= 5) {
      sessionToken = await inputs[4].inputValue();
    }

    if (accessKey && secretKey) {
      console.log(`AWS_ACCESS_KEY_ID=${accessKey.trim()}`);
      console.log(`AWS_SECRET_ACCESS_KEY=${secretKey.trim()}`);
      if (sessionToken) {
        console.log(`AWS_SESSION_TOKEN=${sessionToken.trim()}`);
      }
      return;
    } else {
      throw new Error('Could not find AWS Access Key and Secret Key');
    }

  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  } finally {
    if (_cdpBrowser) {
      await _cdpBrowser.disconnect().catch(() => {});
    } else if (browserContext) {
      await browserContext.close();
    }
  }
}

const OVERALL_TIMEOUT_MS = 600000;
Promise.race([
  extractCredentials(),
  new Promise((_, reject) =>
    setTimeout(() => reject(new Error(`Script timed out after ${OVERALL_TIMEOUT_MS / 1000}s`)), OVERALL_TIMEOUT_MS)
  )
]).catch(err => {
  console.error(`ERROR: ${err.message}`);
  process.exit(1);
});
