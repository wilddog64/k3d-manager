const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');

/**
 * scripts/playwright/acg_extend.js
 *
 * Static Playwright script to extend the ACG sandbox TTL by 4 hours.
 * Launches a persistent Chrome context — session persists across runs via auth dir.
 * Auth dir: ~/.local/share/k3d-manager/playwright-auth
 *
 * Usage: node acg_extend.js <sandbox-url>
 */

const AUTH_DIR = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'playwright-auth');

function _isFirstRun() {
  try {
    return !fs.existsSync(AUTH_DIR) || fs.readdirSync(AUTH_DIR).length === 0;
  } catch {
    return true;
  }
}

async function extendSandbox() {
  if (_isFirstRun()) {
    console.error(`ERROR: Auth dir is empty (${AUTH_DIR}).`);
    console.error('ERROR: Run acg_get_credentials <sandbox-url> first to bootstrap the Pluralsight session.');
    process.exit(1);
  }

  const targetUrl = process.argv[2];
  if (!targetUrl) {
    console.error('ERROR: No sandbox URL provided');
    process.exit(1);
  }

  let browserContext;
  try {
    browserContext = await chromium.launchPersistentContext(AUTH_DIR, {
      headless: false,
      channel: 'chrome',
      args: ['--password-store=basic'],
    });

    const allPages = browserContext.pages();
    let page = allPages.find(p => {
      try { return new URL(p.url()).hostname.endsWith('.pluralsight.com'); } catch { return false; }
    });
    if (!page) {
      page = allPages[0];
      if (!page) throw new Error('No page found in the browser context');
    }

    console.error(`INFO: Navigating to ${targetUrl}...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });

    // Wait for skeleton loaders to clear
    await page.waitForFunction(
      () => !document.querySelector('[aria-busy="true"]'),
      { timeout: 30000 }
    ).catch(() => console.error('WARN: Skeleton loaders did not clear within 30s — proceeding anyway'));

    // Try multiple selector strategies for the extend button
    const extendSelectors = [
      'button:has-text("Extend")',
      'button:has-text("+4")',
      'button:has-text("Add 4")',
      'button:has-text("Renew")',
      '[data-testid*="extend"]',
      '[aria-label*="extend" i]',
    ];

    let clicked = false;
    for (const selector of extendSelectors) {
      const btn = page.locator(selector).first();
      const visible = await btn.isVisible({ timeout: 3000 }).catch(() => false);
      if (visible) {
        console.error(`INFO: Found extend button with selector: ${selector}`);
        await btn.click();
        clicked = true;
        break;
      }
    }

    if (!clicked) {
      // Try opening a sandbox card/panel first — extend button may be inside a slide-over
      const openButton = page.locator('button:has-text("Open Sandbox"), button:has-text("Open")').first();
      const openVisible = await openButton.isVisible({ timeout: 5000 }).catch(() => false);
      if (openVisible) {
        console.error('INFO: Clicking Open to reveal extend button...');
        await openButton.click();
        await page.waitForTimeout(3000);

        for (const selector of extendSelectors) {
          const btn = page.locator(selector).first();
          const visible = await btn.isVisible({ timeout: 3000 }).catch(() => false);
          if (visible) {
            console.error(`INFO: Found extend button (post-open) with selector: ${selector}`);
            await btn.click();
            clicked = true;
            break;
          }
        }
      }
    }

    if (!clicked) {
      throw new Error('Extend button not found or not visible after multiple attempts');
    }

    // Wait for confirmation toast or updated TTL text
    const confirmationSelectors = [
      'text=/extended/i',
      'text=/renewed/i',
      '[role="status"]:has-text("extended")',
      '[data-testid*="toast"]:has-text("Extend")',
    ];

    let confirmed = false;
    for (const selector of confirmationSelectors) {
      const locator = page.locator(selector).first();
      confirmed = await locator.isVisible({ timeout: 10000 }).catch(() => false);
      if (confirmed) {
        console.error(`INFO: Extension confirmed via selector: ${selector}`);
        break;
      }
    }

    if (!confirmed) {
      console.error('WARN: Could not confirm extension via toast/TTL text — proceeding anyway');
    }

    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
    console.log(`Extend action complete. Current expiry text: ${expiryText}`);
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  } finally {
    if (browserContext) await browserContext.close();
  }
}

const OVERALL_TIMEOUT_MS = 90000;
Promise.race([
  extendSandbox(),
  new Promise((_, reject) =>
    setTimeout(() => reject(new Error(`Script timed out after ${OVERALL_TIMEOUT_MS / 1000}s`)), OVERALL_TIMEOUT_MS)
  )
]).catch(err => {
  console.error(`ERROR: ${err.message}`);
  process.exit(1);
});
