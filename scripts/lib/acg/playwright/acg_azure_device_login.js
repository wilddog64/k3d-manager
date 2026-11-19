'use strict';
const { chromium } = require('playwright');
const { CDP_URL } = require('./lib/output');

async function main() {
  const [,, deviceUrl, deviceCode] = process.argv;
  if (!deviceUrl || !deviceCode) {
    console.error('ERROR: Usage: acg_azure_device_login.js <device-url> <device-code>');
    process.exit(1);
  }

  const cdpBrowser = await chromium.connectOverCDP(CDP_URL);
  const context = cdpBrowser.contexts()[0];
  if (!context) {
    console.error('ERROR: No browser context available — is Chrome running with --remote-debugging-port=9222?');
    await cdpBrowser.disconnect().catch(() => {});
    process.exit(1);
  }

  const page = await context.newPage();
  try {
    console.error(`INFO: Navigating to device login: ${deviceUrl}`);
    await page.goto(deviceUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

    const codeInput = page.locator('input[name="otc"]').first();
    await codeInput.waitFor({ state: 'visible', timeout: 15000 });
    await codeInput.fill(deviceCode);
    console.error('INFO: Filled device code.');

    await page.locator('input[type="submit"]').first().click();
    await page.waitForTimeout(2000);

    const confirmBtn = page.locator('input[type="submit"], button').filter({
      hasText: /continue|yes|confirm/i,
    }).first();
    if (await confirmBtn.isVisible({ timeout: 8000 }).catch(() => false)) {
      await confirmBtn.click({ force: true });
      await page.waitForTimeout(2000);
    }

    const bodyText = await page.textContent('body').catch(() => '');
    if (/signed.?in|you.*close|authentication.?complete/i.test(bodyText)) {
      console.error('INFO: Device code sign-in confirmed in browser.');
    } else {
      console.error('INFO: Device code submitted — proceeding.');
    }
    process.exit(0);
  } catch (e) {
    console.error(`ERROR: acg_azure_device_login failed: ${e.message}`);
    process.exit(1);
  } finally {
    await page.close().catch(() => {});
    await cdpBrowser.disconnect().catch(() => {});
  }
}

main().catch(e => {
  console.error(`FATAL: ${e.message}`);
  process.exit(1);
});
