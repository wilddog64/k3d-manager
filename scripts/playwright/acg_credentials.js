const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');

/**
 * scripts/playwright/acg_credentials.js
 *
 * Static Playwright script to extract AWS/GCP credentials from Pluralsight Cloud Sandbox.
 * Reuses existing Chrome context via CDP.
 *
 * Exit Code Contract:
 * 0: SUCCESS          - Credentials extracted
 * 1: ERROR            - Unexpected internal failure
 * 10: LOGIN_REQUIRED  - Session expired, redirected to /id or /hands-on
 * 11: UNEXPECTED_PAGE - CDP attached but no relevant sandbox tab found
 * 12: TIMEOUT         - Dashboard reached but content failed to load
 */

const STATUS = {
  SUCCESS: 0,
  ERROR: 1,
  LOGIN_REQUIRED: 10,
  UNEXPECTED_PAGE: 11,
  TIMEOUT: 12
};

async function _extractAwsCredentials(page) {
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

  if (accessKey && secretKey) {
    console.log(`AWS_ACCESS_KEY_ID=${accessKey.trim()}`);
    console.log(`AWS_SECRET_ACCESS_KEY=${secretKey.trim()}`);
    if (sessionToken) {
      console.log(`AWS_SESSION_TOKEN=${sessionToken.trim()}`);
    }
  } else {
    throw new Error('Could not find AWS Access Key and Secret Key');
  }
}

async function _extractGcpCredentials(page) {
  await page.waitForSelector('text=Username', { timeout: 15000 });
  const inputs = await page.locator('input[aria-label="Copyable input"]').all();
  console.error(`INFO: Found ${inputs.length} copyable inputs`);

  const username = inputs.length >= 1 ? await inputs[0].inputValue().catch(() => '') : '';
  const password = inputs.length >= 2 ? await inputs[1].inputValue().catch(() => '') : '';
  const serviceAccountJson = inputs.length >= 3 ? await inputs[2].inputValue().catch(() => '') : '';

  if (!serviceAccountJson) {
    throw new Error('Could not find Service Account Credentials field');
  }

  let projectId;
  try {
    projectId = JSON.parse(serviceAccountJson).project_id;
  } catch {
    throw new Error('Service Account Credentials is not valid JSON');
  }

  const keyPath = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'gcp-service-account.json');
  fs.writeFileSync(keyPath, serviceAccountJson, { mode: 0o600 });
  console.error(`INFO: Service account key written to ${keyPath}`);

  console.log(`GCP_PROJECT=${projectId}`);
  console.log(`GCP_USERNAME=${username.trim()}`);
  console.log(`GCP_PASSWORD=${password.trim()}`);
  console.log(`GOOGLE_APPLICATION_CREDENTIALS=${keyPath}`);
}

async function extractCredentials() {
  const targetUrl = process.argv[2];
  if (!targetUrl) {
    console.error('ERROR: No target URL provided');
    process.exit(STATUS.ERROR);
  }
  const _providerIdx = process.argv.indexOf('--provider');
  const _provider = _providerIdx !== -1 && process.argv[_providerIdx + 1] ? process.argv[_providerIdx + 1] : 'aws';
  
  console.error(`INFO: Using provider ${_provider}`);

  let browser;
  try {
    // 1. CDP Attach
    try {
      browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
    } catch (e) {
      console.error(`ERROR: Cannot connect to Chrome CDP: ${e.message}`);
      process.exit(STATUS.ERROR);
    }

    const context = browser.contexts()[0];
    if (!context) {
      console.error('ERROR: CDP connected but no browser context found.');
      process.exit(STATUS.ERROR);
    }

    // 2. Tab Discovery and Classification
    const allPages = context.pages();
    let page = allPages.find(p => {
      try { return new URL(p.url()).hostname.includes('pluralsight.com'); } catch { return false; }
    });
    
    if (!page) {
      console.error('INFO: No Pluralsight tab open, opening a new one.');
      page = await context.newPage();
    }

    // 3. Strategic Navigation
    console.error(`INFO: Navigating to ${targetUrl}...`);
    if (!page.url().includes('cloud-sandboxes')) {
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    }

    // 4. Session State Machine (Granular Classification)
    const deadline = Date.now() + 300000;
    while (Date.now() < deadline) {
      const url = page.url();
      
      // State: READY
      if (url.includes('cloud-sandboxes')) {
        console.error('DIAGNOSTIC: Session state is READY (Dashboard reached).');
        break;
      }
      
      // State: LOGIN_REQUIRED
      if (url.includes('/id') || url.includes('/hands-on') || url.includes('/home')) {
        console.error('DIAGNOSTIC: Session state is LOGIN_REQUIRED.');
        console.error('ACTION REQUIRED: Pluralsight session invalid or expired. PLEASE SIGN IN MANUALLY IN CHROME.');
        // We stay in the loop to allow the user to fix it
      } else {
        // State: UNEXPECTED_PAGE
        console.error('DIAGNOSTIC: Session state is UNEXPECTED_PAGE.');
        console.error(`INFO: Attached to non-sandbox URL: ${url}`);
      }
      
      await page.waitForTimeout(5000);
    }

    // Post-loop check
    if (!page.url().includes('cloud-sandboxes')) {
      const finalUrl = page.url();
      if (finalUrl.includes('/id') || finalUrl.includes('/hands-on')) {
        process.exit(STATUS.LOGIN_REQUIRED);
      } else {
        process.exit(STATUS.UNEXPECTED_PAGE);
      }
    }

    // 5. Extraction
    await page.waitForSelector('button:has-text("Sandbox"), input[aria-label="Copyable input"]', { timeout: 30000 })
      .catch(() => { throw new Error('TIMEOUT: Dashboard elements failed to appear'); });
    
    const credInput = page.locator('input[aria-label="Copyable input"]').first();
    const hasCreds = await credInput.isVisible({ timeout: 2000 }).then(async (vis) => vis && (await credInput.inputValue()).length > 0).catch(() => false);
    
    if (!hasCreds) {
      console.error('INFO: Panel not loaded, searching for provider button...');
      const providerLabel = _provider === 'gcp' ? 'GCP' : 'AWS';
      const openBtn = page.locator(`button:has-text("Open Sandbox"), button[data-heap-id*="${providerLabel} Sandbox - Open Sandbox"]`).first();
      
      if (await openBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
        await openBtn.click();
      } else {
        console.error('WARN: Provider button not found. Manual interaction may be required.');
      }
      
      await page.waitForFunction(() => {
        const el = document.querySelector('input[aria-label="Copyable input"]');
        return el && el.value.trim().length > 0;
      }, { timeout: 45000 }).catch(() => { throw new Error('TIMEOUT: Credentials failed to populate in panel'); });
    }

    console.error(`INFO: Extracting credentials...`);
    if (_provider === 'aws') {
      await _extractAwsCredentials(page);
    } else {
      await _extractGcpCredentials(page);
    }

  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(error.message.includes('TIMEOUT') ? STATUS.TIMEOUT : STATUS.ERROR);
  } finally {
    if (browser) {
      await browser.disconnect().catch(() => {});
      console.error('INFO: Disconnected from CDP session.');
    }
  }
}

const OVERALL_TIMEOUT_MS = 360000;
Promise.race([
  extractCredentials(),
  new Promise((_, reject) =>
    setTimeout(() => reject(new Error(`Script timed out after ${OVERALL_TIMEOUT_MS / 1000}s`)), OVERALL_TIMEOUT_MS)
  )
]).catch(err => {
  console.error(`ERROR: ${err.message}`);
  process.exit(STATUS.TIMEOUT);
});
