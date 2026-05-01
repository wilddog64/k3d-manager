const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');

/**
 * scripts/playwright/acg_extend.js
 *
 * Static Playwright script to extend the ACG sandbox TTL by 4 hours.
 * Launches a persistent Chrome context — session persists across runs via auth dir.
 * Auth dir: ~/.local/share/k3d-manager/profile
 *
 * Usage: node acg_extend.js <sandbox-url>
 */

const AUTH_DIR = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'profile');

function _isFirstRun() {
  try {
    return !fs.existsSync(AUTH_DIR) || fs.readdirSync(AUTH_DIR).length === 0;
  } catch {
    return true;
  }
}

async function _waitForVisibleExtendButton(page, selectors, timeoutMs, phaseLabel) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() <= deadline) {
    const remainingMs = Math.max(0, deadline - Date.now());
    if (remainingMs === 0 && timeoutMs > 0) {
      break;
    }

    for (const selector of selectors) {
      const btn = page.locator(selector).first();
      const visible = await btn.isVisible({ timeout: remainingMs }).catch(() => false);
      if (visible) {
        console.error(`INFO: Found extend button${phaseLabel ? ` (${phaseLabel})` : ''} with selector: ${selector}`);
        return btn;
      }
    }

    if (Date.now() < deadline) {
      await page.waitForTimeout(500);
    }
  }

  return null;
}

function _sanitizePhaseLabel(phaseLabel) {
  return phaseLabel
    ? phaseLabel.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '')
    : '';
}

async function _captureExtendFailure(page, phaseLabel) {
  const diagnosticsDir = path.join(os.homedir(), '.local', 'share', 'k3d-manager');
  const safePhaseLabel = _sanitizePhaseLabel(phaseLabel);
  const screenshotPath = path.join(
    diagnosticsDir,
    `acg-extend-failure-${Date.now()}${safePhaseLabel ? `-${safePhaseLabel}` : ''}.png`
  );

  try {
    await fs.promises.mkdir(diagnosticsDir, { recursive: true });
    await page.screenshot({ path: screenshotPath, fullPage: true });
    console.error(`INFO: Saved extend failure screenshot to ${screenshotPath}`);
  } catch (err) {
    console.error(`WARN: Could not save extend failure screenshot: ${err.message}`);
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
    let isPluralsight = false;
    try {
      const parsedUrl = new URL(currentUrl);
      isPluralsight = parsedUrl.hostname === 'pluralsight.com' || parsedUrl.hostname.endsWith('.pluralsight.com');
    } catch { isPluralsight = false; }
    if (isPluralsight) {
      console.error(`INFO: Already on Pluralsight page: ${currentUrl}`);
    } else {
      console.error(`INFO: Navigating to ${targetUrl}...`);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    }

    // Dismiss any lingering "Session extended" confirmation modal before searching for extend button
    const _sessionExtendedModal = page.locator('text="Session extended"').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(500);
      // Fallback: click the X button if Escape didn't close it
      const _closeBtn = page.locator('[role="dialog"] button, button:has-text("×"), button[aria-label*="close" i]').first();
      if (await _sessionExtendedModal.isVisible({ timeout: 1000 }).catch(() => false) &&
          await _closeBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
        await _closeBtn.click({ force: true }).catch(() => {});
        await page.waitForTimeout(500);
      }
      // Confirm the modal is gone before proceeding — guards against slow close animations
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 3s — proceeding anyway');
      });
    }

    // Wait for skeleton loaders to clear
    await page.waitForFunction(
      () => !document.querySelector('[aria-busy="true"]'),
      { timeout: 30000 }
    ).catch(() => console.error('WARN: Skeleton loaders did not clear within 30s — proceeding anyway'));

    // 1. "Button First" check — if the modal is already open, just click it and finish.
    const extendSelectors = [
      '[data-heap-id="Hands-on Playground - Click - AWS Sandbox - Extend Sandbox"]',
      '[data-heap-id*="Extend Sandbox"]',
      '[data-heap-id*="Extend Session"]',
      'button:has-text("Extend Session")',
      'button:has-text("Extend Sandbox")',
      '[id="extend-sandbox"] button',
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
    const immediateBtn = await _waitForVisibleExtendButton(page, extendSelectors, 0, 'immediately');
    if (immediateBtn) {
      await immediateBtn.click({ force: true });
      clicked = true;
    }

    if (clicked) {
      console.log('Extend action complete (Immediate).');
      return;
    }

    // 2. Try to parse TTL and exit gracefully if > 1 hour remains
    // Use a broader text-based locator for the shutdown title
    const shutdownTitleLoc = page.locator('text=/Auto Shutdown/i').first();
    let remainingMins = null;

    if (await shutdownTitleLoc.isVisible({ timeout: 10000 }).catch(() => false)) {
      // Get text from parent to ensure we capture the time (which might be in a sibling <p>)
      const shutdownText = await shutdownTitleLoc.evaluate(el => el.parentElement.innerText).catch(() => '');
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
          
          // Midnight/Date-wrap fix: Handle case where shutdown is tomorrow morning
          if (shutdownTime < now) {
             shutdownTime.setDate(shutdownTime.getDate() + 1);
          }
          
          const remainingMs = shutdownTime.getTime() - now.getTime();
          remainingMins = Math.floor(remainingMs / 60000);
          
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
      console.error(`WARN: Auto Shutdown text not found. Proceeding anyway.`);
    }

    // 3. Reveal the panel/modal if still not clicked
    // isPanelOpen: "Auto Shutdown" text appears on the listing-page card — not a reliable signal
    // that the extend panel is open. If step 1 found no extend button, the panel is NOT open.
    const isPanelOpen = clicked;

    if (!isPanelOpen) {
      // Click "Open Sandbox" on the card with the "Auto Shutdown" banner (the running sandbox),
      // not .first() which always picks the first card (AWS) regardless of provider.
      const _allOpenBtns = page.locator('button:has-text("Open Sandbox")');
      const _btnCount = await _allOpenBtns.count();
      let _openBtn = null;
      for (let _i = 0; _i < _btnCount; _i++) {
        const _hasShutdown = await _allOpenBtns.nth(_i).evaluate(el => {
          let node = el.parentElement;
          for (let _j = 0; _j < 6; _j++) {
            if (!node) break;
            if (/auto\s*shutdown/i.test(node.innerText || '')) return true;
            node = node.parentElement;
          }
          return false;
        }).catch(() => false);
        if (_hasShutdown) { _openBtn = _allOpenBtns.nth(_i); break; }
      }
      if (!_openBtn) {
        _openBtn = page.locator('button:has-text("Open Sandbox"), button:has-text("Start Sandbox"), button:has-text("Resume")').first();
      }
      if (await _openBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Open Sandbox to reveal extend panel...');
        await _openBtn.click({ force: true });
        const _openPanelBtn = await _waitForVisibleExtendButton(page, extendSelectors, 15000, 'after Open Sandbox');
        if (_openPanelBtn) {
          await _openPanelBtn.click({ force: true });
          clicked = true;
        }
      }
    }

    // 5. "Ghost State" Recovery: If still not clicked and TTL is confirmed critical, Delete and Restart
    // Only trigger when remainingMins is definitively known to be critical — never on null (TTL parse
    // failure alone is not a strong enough signal to perform a destructive delete/restart action)
    if (!clicked && remainingMins !== null && remainingMins < 15) {
      console.error('INFO: Extend button missing in critical window. Attempting "Ghost State" recovery (Delete/Restart)...');
      
      const deleteBtn = page.locator('button:has-text("Delete Sandbox")').first();
      if (await deleteBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Delete Sandbox...');
        await deleteBtn.click({ force: true });
        
        const confirmBtn = page.locator('div[role="dialog"] button:has-text("Delete"), button:has-text("Confirm"), button:has-text("Yes, delete")').first();
        if (await confirmBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
          await confirmBtn.click({ force: true });
          console.error('INFO: Deletion confirmed. Waiting for Start button...');
          await page.waitForTimeout(5000);
          
          const startBtn = page.locator('button:has-text("Start Sandbox")').first();
          if (await startBtn.isVisible({ timeout: 30000 }).catch(() => false)) {
            console.error('INFO: Clicking Start Sandbox...');
            await startBtn.click({ force: true });
            
            // Pluralsight should now show the "Extend Your Session" modal
            console.error('INFO: Waiting for Extension Modal...');
            const _recoveryBtn = await _waitForVisibleExtendButton(page, extendSelectors, 20000, 'after recovery');
            if (_recoveryBtn) {
              await _recoveryBtn.click({ force: true });
              clicked = true;
            }
          }
        }
      }
    }

    if (!clicked) {
      await _captureExtendFailure(page, 'missing-extend-button');
      throw new Error('Extend button not found or not visible after multiple attempts (including recovery)');
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
    // Only close if we launched a persistent context (not if we attached via CDP — closing a CDP
    // browser shuts down the entire Chrome process, disrupting other sessions)
    if (!_cdpBrowser && browserContext) {
      await browserContext.close().catch(() => {});
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
