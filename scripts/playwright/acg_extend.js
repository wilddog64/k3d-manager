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

  let targetUrl = process.argv[2];
  if (!targetUrl) {
    console.error('ERROR: No sandbox URL provided');
    process.exit(1);
  }
  // Standardize URL to minimize SPA redirects
  if (targetUrl.includes('cloud-playground/cloud-sandboxes')) {
    targetUrl = targetUrl.replace('cloud-playground/cloud-sandboxes', 'hands-on/playground/cloud-sandboxes');
  }

  let browserContext;
  let _cdpBrowser = null;
  try {
    // Try to connect via CDP first to catch already-open modals
    try {
      _cdpBrowser = await chromium.connectOverCDP('http://localhost:9222');
      const _cdpContexts = _cdpBrowser.contexts();
      if (_cdpContexts.length > 0) {
        browserContext = _cdpContexts[0];
        console.error('INFO: Connected via CDP to existing browser session.');
      }
    } catch (e) {
      // CDP failed, fall back to persistent context
      _cdpBrowser = null;
    }

    if (!browserContext) {
      browserContext = await chromium.launchPersistentContext(AUTH_DIR, {
        headless: false,
        channel: 'chrome',
        args: ['--password-store=basic'],
      });
    }

    const allPages = browserContext.pages();
    let page = allPages.find(p => {
      try { return new URL(p.url()).hostname.endsWith('.pluralsight.com'); } catch { return false; }
    });
    if (!page) {
      page = allPages[0];
      if (!page) throw new Error('No page found in the browser context');
    }

    const currentUrl = page.url();
    if (currentUrl.includes('pluralsight.com')) {
      console.error(`INFO: Already on Pluralsight page: ${currentUrl}`);
    } else {
      console.error(`INFO: Navigating to ${targetUrl}...`);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    }

    // Wait for skeleton loaders to clear
    await page.waitForFunction(
      () => !document.querySelector('[aria-busy="true"]'),
      { timeout: 30000 }
    ).catch(() => console.error('WARN: Skeleton loaders did not clear within 30s — proceeding anyway'));

    // Wait for actual content cards to render
    await page.waitForSelector('[data-testid*="sandbox-card"], button:has-text("Open Sandbox")', { timeout: 15000 })
      .catch(() => console.error('WARN: Sandbox cards not found after 15s.'));

    // Check if the details panel is already open
    const isPanelOpen = await page.locator('[data-testid="auto-shutdown-title"]').isVisible({ timeout: 2000 }).catch(() => false);
    
    if (!isPanelOpen) {
      // Try opening a sandbox card/panel first to ensure TTL and extend buttons are rendered
      const openButton = page.locator('button:has-text("Open Sandbox"), button:has-text("Open"), button:has-text("Start Sandbox"), button:has-text("Resume")').first();
      const openVisible = await openButton.isVisible({ timeout: 15000 }).catch(() => false);
      if (openVisible) {
        console.error('INFO: Clicking Open to reveal sandbox details...');
        // Use force click because Pluralsight SPAs often have invisible overlays
        await openButton.click({ force: true });
        await page.waitForTimeout(5000); // Wait for slide-over/modal animation
      }
    } else {
      console.error('INFO: Sandbox details panel already visible — skipping Open click.');
    }

    // Try to parse TTL and exit gracefully if > 1 hour remains
    // Use a broader text-based locator for the shutdown title
    const shutdownTitleLoc = page.locator('text=/Auto Shutdown/i').first();
    const hasShutdownTitle = await shutdownTitleLoc.isVisible({ timeout: 10000 }).catch(() => false);
    
    if (hasShutdownTitle) {
      // Get text from parent to ensure we capture the time (which might be in a sibling <p>)
      const shutdownText = await shutdownTitleLoc.evaluate(el => el.parentElement.innerText).catch(() => '');
      console.error(`INFO: Detected shutdown text: ${shutdownText.replace(/\n/g, ' ')}`);
      const match = shutdownText.match(/at\s+(\d{1,2}:\d{2}(?:\s*)(?:AM|PM|am|pm))/i);
      if (match) {
        const timeStr = match[1].replace(/\s+/g, '');
        const now = new Date();
        const shutdownMatch = timeStr.match(/(\d+):(\d+)(AM|PM|am|pm)/i);
        if (shutdownMatch) {
          let hours = parseInt(shutdownMatch[1], 10);
          const mins = parseInt(shutdownMatch[2], 10);
          const ampm = shutdownMatch[3].toUpperCase();
          if (ampm === 'PM' && hours < 12) hours += 12;
          if (ampm === 'AM' && hours === 12) hours = 0;
          
          const shutdownTime = new Date();
          shutdownTime.setHours(hours, mins, 0, 0);
          
          // Handle case where shutdown is tomorrow morning (e.g. now is 11 PM, shutdown is 2 AM)
          if (shutdownTime < now && (now.getHours() > 12 && hours < 12)) {
             shutdownTime.setDate(shutdownTime.getDate() + 1);
          }
          
          const remainingMs = shutdownTime.getTime() - now.getTime();
          const remainingMins = Math.floor(remainingMs / 60000);
          
          console.error(`INFO: Calculated remaining TTL: ~${remainingMins} minutes`);
          
          if (remainingMins > 65) {
            console.log(`INFO: Extension window not open yet (${remainingMins}m remaining). Skipping extension.`);
            process.exit(0);
          } else {
            console.error(`INFO: Within 1h extension window (${remainingMins}m remaining). Proceeding to extend...`);
          }
        }
      }
    } else {
      console.error(`WARN: Auto Shutdown text not found. Proceeding to search for Extend button anyway.`);
    }

    // Try multiple selector strategies for the extend button
    const extendSelectors = [
      '[data-heap-id="Hands-on Playground - Click - AWS Sandbox - Extend Sandbox"]',
      '[data-heap-id*="Extend Sandbox"]',
      '[data-heap-id*="Extend Session"]',
      'button:has-text("Extend Session")',
      'button:has-text("Extend Sandbox")',
      '[id="extend-sandbox"] button',
      'h4:has-text("Extend Your Session")',
      'text="Extend Session"',
      'text="Extend Your Session"',
      'a:has-text("Extend Session")',
      '[role="button"]:has-text("Extend Session")',
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
      const visible = await btn.isVisible({ timeout: 5000 }).catch(() => false);
      if (visible) {
        console.error(`INFO: Found extend button with selector: ${selector}`);
        await btn.click();
        clicked = true;
        break;
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
    if (_cdpBrowser) {
      await _cdpBrowser.close().catch(() => {});
    } else if (browserContext) {
      await browserContext.close();
    }
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
