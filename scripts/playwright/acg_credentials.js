const { chromium } = require('playwright');

/**
 * scripts/playwright/acg_credentials.js
 * 
 * Static Playwright script to extract AWS credentials from Pluralsight Cloud Sandbox.
 * Connects to a running instance via CDP.
 */

async function extractCredentials() {
  const targetUrl = process.argv[2];
  if (!targetUrl) {
    console.error('ERROR: No target URL provided');
    process.exit(1);
  }

  let browser;
  try {
    // 1. Connect to the running browser via CDP
    browser = await chromium.connectOverCDP('http://localhost:9222');

    // 2. Find the Pluralsight page by URL (do not assume pages()[0])
    const context = browser.contexts()[0];
    if (!context) throw new Error('No browser context found');
    const allPages = context.pages();
    let page = allPages.find(p => p.url().includes('pluralsight.com'));
    if (!page) {
      page = allPages[0];
      if (!page) throw new Error('No page found in the browser context');
    }

    // Navigate only if not already on the target URL (hard reload kills SPA auth)
    const currentUrl = page.url();
    if (!currentUrl.startsWith('https://app.pluralsight.com')) {
      console.error(`INFO: Navigating to ${targetUrl}...`);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    } else if (!currentUrl.includes('cloud-sandboxes')) {
      console.error(`INFO: SPA-navigating to cloud-sandboxes from ${currentUrl}...`);
      const navLink = page.locator('a[href*="cloud-sandboxes"]').first();
      const navVisible = await navLink.isVisible({ timeout: 5000 }).catch(() => false);
      if (navVisible) {
        await navLink.click();
      } else {
        await page.evaluate(url => window.location.assign(url), targetUrl);
      }
    } else {
      console.error(`INFO: Already on ${currentUrl} — skipping navigation`);
    }

    // Give it time to render SPA content after navigation changes
    console.error('INFO: Waiting for page content to load...');
    await page.waitForFunction(
      () => !document.querySelector('[aria-busy="true"]'),
      { timeout: 30000 }
    ).catch(() => console.error('WARN: Skeleton loaders did not clear within 30s — proceeding anyway'));

    // 3. Handle Sandbox Start/Open Flow
    console.error('INFO: Looking for Start/Open button...');
    
    // Pattern 1: Direct "Start Sandbox" button (in a modal or panel)
    const startButton = page.locator('button:has-text("Start Sandbox")').first();
    // Pattern 2: "Open Sandbox" button (on the card)
    const openButton = page.locator('button:has-text("Open Sandbox")').first();
    // Pattern 3: "Resume Sandbox"
    const resumeButton = page.locator('button:has-text("Resume"), button:has-text("Resume Sandbox")').first();

    if (await startButton.isVisible()) {
      console.error('INFO: Clicking Start Sandbox...');
      await startButton.click();
      await page.waitForTimeout(10000);
    } else if (await openButton.isVisible()) {
      console.error('INFO: Clicking Open Sandbox...');
      await openButton.click();
      await page.waitForTimeout(10000);
      
      // After Open, there might be a Start Sandbox button in the slide-over
      const startButton2 = page.locator('button:has-text("Start Sandbox")').first();
      if (await startButton2.isVisible()) {
        console.error('INFO: Clicking Start Sandbox (Step 2)...');
        await startButton2.click();
        await page.waitForTimeout(10000);
      }
    } else if (await resumeButton.isVisible()) {
      console.error('INFO: Clicking Resume Sandbox...');
      await resumeButton.click();
      await page.waitForTimeout(10000);
    }

    // 4. Extract credentials
    console.error('INFO: Extracting credentials...');
    
    // We found that credentials are in inputs with aria-label="Copyable input"
    // The order is typically: Username, Password, Access Key ID, Secret Access Key, [Session Token]
    
    // Wait for the inputs to appear
    await page.waitForSelector('input[aria-label="Copyable input"]', { timeout: 60000 });
    
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
      process.exit(0);
    } else {
      throw new Error('Could not find AWS Access Key and Secret Key');
    }

  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  } finally {
    if (browser) await browser.close();
  }
}

extractCredentials();
