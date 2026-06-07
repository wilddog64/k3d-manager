async function findOrCreatePage(context) {
  const allPages = context.pages();
  let page = allPages.find(p => {
    try {
      return p.url().includes('cloud-playground/cloud-sandboxes') || p.url().includes('hands-on/playground/cloud-sandboxes');
    } catch {
      return false;
    }
  });

  if (!page) {
    console.error('INFO: No existing sandbox tab found — opening new extraction tab.');
    page = await context.newPage();
    page.__libAcgWasCreated = true;
  } else {
    console.error(`INFO: Found existing sandbox tab: ${page.url()}`);
  }

  return page;
}

async function navigateToSandbox(page, targetUrl) {
  const _sandboxReady = await page.locator(
    'button:has-text("Start Sandbox"), input[aria-label="Copyable input"]'
  ).first().isVisible({ timeout: 2000 }).catch(() => false);
  if (_sandboxReady) {
    console.error('INFO: Sandbox panel already loaded — skipping navigation');
    return;
  }

  const currentUrl = page.url();
  let currentHostname = '';
  try { currentHostname = new URL(currentUrl).hostname; } catch {}
  let targetPathname = '';
  try { targetPathname = new URL(targetUrl).pathname; } catch {}
  let currentPathname = '';
  try { currentPathname = new URL(currentUrl).pathname; } catch {}

  if (currentHostname !== 'app.pluralsight.com') {
    console.error(`INFO: Navigating to ${targetUrl}...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
  } else if (currentPathname === targetPathname) {
    console.error(`INFO: Already on ${currentUrl} — skipping navigation`);
  } else if (targetPathname.includes('cloud-sandboxes')) {
    console.error(`INFO: SPA-navigating to cloud-sandboxes from ${currentUrl}...`);
    // navLink.click() follows href to s2.pluralsight.com (404); also times out if
    // the Extend Your Session dialog reappears between dismiss and click.
    await page.evaluate(url => window.location.assign(url), targetUrl);
    await page.waitForLoadState('domcontentloaded', { timeout: 60000 }).catch(() => {});
  } else {
    console.error(`INFO: Navigating to ${targetUrl}...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
  }
}

async function waitForSkeleton(page) {
  console.error('INFO: Waiting for page content to load...');
  await page.waitForFunction(
    () => !document.querySelector('[aria-busy="true"]'),
    { timeout: 30000 }
  ).catch(() => console.error('WARN: Skeleton loaders did not clear within 30s — proceeding anyway'));
}

async function handleSignIn(page, targetUrl) {
  const signInLink = page.locator('a[href*="id.pluralsight.com"], a:has-text("Sign In"), button:has-text("Sign In")').first();
  const isSignInVisible = await signInLink.isVisible({ timeout: 10000 }).catch(() => false);
  if (!isSignInVisible) {
    return;
  }

  console.error('INFO: Not signed in — clicking Sign In...');
  await signInLink.click();
  await page.waitForURL('**id.pluralsight.com**', { timeout: 300000 });

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

  const continueBtn = page.locator('button[type="submit"], button:has-text("Continue")').first();
  if (await continueBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
    await continueBtn.click();
    await page.waitForTimeout(3000);
  }

  const passwordInput = page.locator('input[type="password"]').first();
  if (await passwordInput.isVisible({ timeout: 10000 }).catch(() => false)) {
    await passwordInput.click();
    await page.waitForTimeout(5000);
    const submitBtn = page.locator('button[type="submit"], button:has-text("Sign in"), button:has-text("Log in")').first();
    if (await submitBtn.isVisible({ timeout: 10000 }).catch(() => false)) {
      await submitBtn.click();
      console.error('INFO: Submitted sign-in form — waiting for redirect...');
    }
  }

  await page.waitForURL('**app.pluralsight.com**', { timeout: 300000 });
  console.error('INFO: Sign-in complete — resuming credential extraction...');

  await page.waitForFunction(
    () => !document.querySelector('[aria-busy="true"]'),
    { timeout: 30000 }
  ).catch(() => console.error('WARN: Skeleton loaders did not clear after login — proceeding anyway'));
}

async function _waitForSandboxEntry(page, timeout = 30000) {
  await page.waitForFunction(() => {
    const buttons = Array.from(document.querySelectorAll('button'));
    const hasStart = buttons.some(b => b.textContent.trim().includes('Start Sandbox'));
    const hasOpen = buttons.some(b => b.textContent.trim().includes('Open Sandbox'));
    const hasResume = buttons.some(b => b.textContent.trim().includes('Resume'));
    const inputs = document.querySelectorAll('input[aria-label="Copyable input"]');
    const hasCredentials = inputs.length > 0 && inputs[0].value.trim().length > 0;
    const hasExtendDialog = Array.from(document.querySelectorAll('[role="dialog"]'))
      .some(d => (d.innerText || '').includes('Extend Your Session'));
    return hasStart || hasOpen || hasResume || hasCredentials || hasExtendDialog;
  }, null, { timeout });
}

async function _waitForSandboxEntrySoft(page, timeout = 30000) {
  try {
    await _waitForSandboxEntry(page, timeout);
    return true;
  } catch {
    return false;
  }
}

async function _dismissExtendYourSessionDialog(page) {
  const dialogVisible = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[role="dialog"]'))
      .some(d => (d.innerText || '').includes('Extend Your Session'))
  ).catch(() => false);
  if (!dialogVisible) return;

  console.error('INFO: "Extend Your Session" dialog detected — clicking Extend button...');
  await page.bringToFront();
  const extendBtn = page.locator(
    '[data-testid="extend-sandbox-modal"] button:has-text("Extend"), [role="alertdialog"] button:has-text("Extend"), [role="dialog"] button:has-text("Extend")'
  ).first();
  const extendVisible = await extendBtn.isVisible({ timeout: 2000 }).catch(() => false);
  if (extendVisible) {
    await extendBtn.click().catch(() => {});
  } else {
    await page.keyboard.press('Enter').catch(() => {});
  }
  await page.waitForTimeout(1000);
  const dialogClosed = await page.waitForFunction(
    () => !Array.from(document.querySelectorAll('[role="dialog"]'))
      .some(d => (d.innerText || '').includes('Extend Your Session')),
    { timeout: 5000 }
  ).then(() => true).catch(() => false);
  if (!dialogClosed) {
    console.error('WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing');
  }
}

async function _waitForCredentials(page) {
  console.error('INFO: Waiting for credentials to populate (up to 420s)...');
  const deadline = Date.now() + 420000;
  while (Date.now() < deadline) {
    await _dismissExtendYourSessionDialog(page);
    const inputs = page.locator('input[aria-label="Copyable input"]');
    if (await inputs.count() > 0) {
      const value = await inputs.first().inputValue().catch(() => '');
      if (value.trim().length > 0) {
        return;
      }
    }
    await page.waitForTimeout(2000);
  }
  throw new Error('Locator polling timed out after 420000ms waiting for input[aria-label="Copyable input"] to have a non-empty value.');
}

async function startSandbox(page, targetUrl) {
  const firstCredInput = page.locator('input[aria-label="Copyable input"]').first();
  const firstCredVisible = await firstCredInput.isVisible({ timeout: 3000 }).catch(() => false);
  const firstCredValue = firstCredVisible ? await firstCredInput.inputValue().catch(() => '') : '';
  const credentialsAlreadyVisible = firstCredVisible && firstCredValue.trim().length > 0;
  if (credentialsAlreadyVisible) {
    console.error('INFO: Credentials already populated — skipping Start/Open flow');
    return;
  }

  console.error('INFO: Looking for Start/Open button...');
  await page.addLocatorHandler(
    page.locator('text=/sandbox has been extended/i'),
    async () => { await page.waitForTimeout(500); }
  ).catch(() => {});
  await _dismissExtendYourSessionDialog(page);
  let sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  const retryPathname = (() => {
    try { return new URL(targetUrl).pathname; } catch { return ''; }
  })();
  if (!sandboxEntryReady && retryPathname.includes('cloud-sandboxes') && !page.url().includes('cloud-sandboxes')) {
    console.error(`INFO: Sandbox route not active (${page.url()}) — retrying via Hands-on route...`);
    await page.goto('https://app.pluralsight.com/hands-on', { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForFunction(() => {
      return document.readyState === 'complete' ||
        Boolean(document.querySelector('a[href*="cloud-sandboxes"]')) ||
        document.body.innerText.includes('Cloud Sandboxes');
    }, { timeout: 15000 }).catch(() => console.error('WARN: Hands-on route did not settle before sandbox retry'));
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  }
  await _dismissExtendYourSessionDialog(page);
  if (!sandboxEntryReady) {
    console.error('WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway');
  }

  const startButton = page.locator('button:has-text("Start Sandbox")').first();
  const openButton = page.locator('button:has-text("Open Sandbox")').first();
  const resumeButton = page.locator('button:has-text("Resume"), button:has-text("Resume Sandbox")').first();

  if (await startButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    const startEnabled = await startButton.isEnabled({ timeout: 1000 }).catch(() => false);
    if (startEnabled) {
      console.error('INFO: Clicking Start Sandbox...');
      await startButton.scrollIntoViewIfNeeded().catch(() => {});
      await startButton.click({ force: true });
    } else {
      console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
    }
    await _waitForCredentials(page);
  } else if (await openButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Clicking Open Sandbox...');
    await openButton.click({ force: true });
    await page.waitForTimeout(3000);

    const startButton2 = page.locator('button:has-text("Start Sandbox")').first();
    if (await startButton2.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.error('INFO: Clicking Start Sandbox (Step 2)...');
      await startButton2.scrollIntoViewIfNeeded().catch(() => {});
      await startButton2.click({ force: true });
    }
    await _waitForCredentials(page);
  } else if (await resumeButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Clicking Resume Sandbox...');
    await resumeButton.scrollIntoViewIfNeeded().catch(() => {});
    await resumeButton.click({ force: true });
    await _waitForCredentials(page);
  }
}

module.exports = {
  findOrCreatePage,
  navigateToSandbox,
  waitForSkeleton,
  handleSignIn,
  startSandbox,
};
