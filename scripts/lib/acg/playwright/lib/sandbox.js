const fs = require('fs');
const os = require('os');
const path = require('path');

const SCREENSHOT_DIR = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'screenshots');

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
  } else if (currentPathname === targetPathname || currentPathname.startsWith(targetPathname)) {
    // Already on the target page or a sandbox-specific subpath (e.g. /cloud-sandboxes/<id>)
    console.error(`INFO: Already on ${currentUrl} — skipping navigation`);
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
    Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="alertdialog"], [role="dialog"]'))
      .some(d => (d.innerText || '').includes('Extend Your Session'))
  ).catch(() => false);
  if (!dialogVisible) return;

  const extendBtn = page.locator(
    '[data-testid="extend-sandbox-modal"] button:has-text("Extend"), [role="alertdialog"] button:has-text("Extend"), [role="dialog"] button:has-text("Extend")'
  ).first();
  const extendVisible = await extendBtn.isVisible({ timeout: 2000 }).catch(() => false);
  if (!extendVisible) return;

  console.error('INFO: "Extend Your Session" dialog detected — clicking Extend button...');
  await page.bringToFront();
  await extendBtn.click({ force: true }).catch(() => {});
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

async function _capturePageDebugState(page, label, reason) {
  const safeLabel = String(label || 'page').toLowerCase().replace(/[^a-z0-9]+/g, '-');
  const screenshotPath = path.join(SCREENSHOT_DIR, `k3dm-${safeLabel}-${Date.now()}.png`);
  let currentUrl = '';
  let visibleText = '';

  try { currentUrl = page.url(); } catch {}
  try {
    visibleText = await page.evaluate(() => (document.body && document.body.innerText) ? document.body.innerText : '');
  } catch {
    visibleText = '';
  }

  try {
    await fs.promises.mkdir(SCREENSHOT_DIR, { recursive: true });
    await page.screenshot({ path: screenshotPath, fullPage: true });
    console.error(`INFO: Screenshot saved to ${screenshotPath}`);
  } catch (error) {
    console.error(`WARN: Failed to capture screenshot for ${safeLabel}: ${error.message}`);
  }

  if (currentUrl) {
    console.error(`INFO: Current URL: ${currentUrl}`);
  }
  if (visibleText) {
    const summary = visibleText.replace(/\s+/g, ' ').trim().slice(0, 1200);
    if (summary) {
      console.error(`INFO: Visible text: ${summary}`);
    }
  }
  if (reason) {
    console.error(`WARN: ${reason}`);
  }

  return { screenshotPath, currentUrl, visibleText };
}

async function _waitForCredentials(page, providerLabel) {
  console.error(`INFO: Waiting for ${providerLabel} credentials to populate (up to 420s)...`);
  const deadline = Date.now() + 420000;
  let reopenCount = 0;
  let partialCredsFirstSeen = 0;
  let deleteCycleCount = 0;
  while (Date.now() < deadline) {
    await _dismissExtendYourSessionDialog(page);
    const inputs = page.locator('input[aria-label="Copyable input"]');
    const inputCount = await inputs.count().catch(() => 0);
    if (inputCount > 0) {
      const vals = await Promise.all(
        Array.from({ length: inputCount }, (_, i) => inputs.nth(i).inputValue().catch(() => ''))
      );
      if (vals.every(v => v.trim().length > 0)) return;
      if (partialCredsFirstSeen === 0 && vals.some(v => v.trim().length > 0)) partialCredsFirstSeen = Date.now();
      if (
        providerLabel === 'Azure' &&
        partialCredsFirstSeen > 0 &&
        Date.now() - partialCredsFirstSeen > 60000 &&
        deleteCycleCount < 3
      ) {
        const deleteBtn = await _findScopedButton(page, 'Delete Sandbox', providerLabel, 5000);
        if (deleteBtn) {
          deleteCycleCount++;
          console.error(`INFO: Azure SP credentials not populated after 60s — deleting sandbox and starting fresh (cycle ${deleteCycleCount}/3)...`);
          await deleteBtn.click({ force: true }).catch(() => {});
          const confirmBtn = page.locator('[role="alertdialog"] button', { hasText: /delete sandbox/i }).first();
          if (await confirmBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
            await confirmBtn.click({ force: true }).catch(() => {});
          }
          console.error(`INFO: Waiting for Azure sandbox deletion (up to 180s)...`);
          const startAfterDelete = await _findScopedButton(page, 'Start Sandbox', providerLabel, 180000);
          if (startAfterDelete) {
            console.error('INFO: Azure sandbox deleted — clicking Start Sandbox...');
            await startAfterDelete.click({ force: true }).catch(() => {});
          } else {
            console.error('WARN: Start Sandbox not found after deletion — continuing to wait...');
          }
        } else {
          console.error('WARN: Delete Sandbox button not found — cannot restart sandbox automatically');
        }
        partialCredsFirstSeen = 0;
        reopenCount = 0;
        await page.waitForTimeout(5000);
        continue;
      }
      // Panel open but credentials not yet populated — check for provider-scoped Start Sandbox.
      // Walk up to 20 ancestors with provider-exclusion: stops when a node contains providerLabel
      // but not any other provider keyword, to avoid matching shared card-grid ancestors.
      const allStart = page.locator('button:has-text("Start Sandbox")');
      const startCount = await allStart.count().catch(() => 0);
      let panelStartBtn = null;
      for (let i = 0; i < startCount; i++) {
        const btn = allStart.nth(i);
        const visible = await btn.isVisible({ timeout: 300 }).catch(() => false);
        if (!visible) continue;
        const disabled = await btn.isDisabled({ timeout: 300 }).catch(() => false);
        if (disabled) continue;
        const inTargetPanel = await btn.evaluate((el, pLabel) => {
          const others = ['AWS', 'Google Cloud', 'GCP', 'Azure'].filter(
            p => !new RegExp(p, 'i').test(pLabel)
          );
          let node = el.parentElement;
          for (let j = 0; j < 20; j++) {
            if (!node) break;
            const t = node.innerText || '';
            if (new RegExp(pLabel, 'i').test(t) && !others.some(p => t.includes(p))) return true;
            if (new RegExp(pLabel, 'i').test(t) && others.some(p => t.includes(p))) break;
            node = node.parentElement;
          }
          return false;
        }, providerLabel).catch(() => false);
        if (inTargetPanel) { panelStartBtn = btn; break; }
      }
      if (panelStartBtn) {
        console.error(`INFO: ${providerLabel} panel open but sandbox not started — clicking Start Sandbox...`);
        await panelStartBtn.click({ force: true }).catch(() => {});
        await page.waitForTimeout(5000);
        continue;
      }
      await page.waitForTimeout(2000);
      continue;
    }
    const reopenBtn = await _findScopedButton(page, 'Open Sandbox', providerLabel, 0);
    if (reopenBtn) {
      const provisioning = await page.evaluate(() => {
        const t = document.body ? (document.body.innerText || '') : '';
        return t.includes('Hang tight') || t.includes('Finalizing your playground');
      }).catch(() => false);
      if (provisioning) {
        console.error(`INFO: ${providerLabel} sandbox is provisioning — waiting before reopening panel...`);
        await page.waitForTimeout(5000);
        continue;
      }
      if (reopenCount >= 3) {
        await _capturePageDebugState(page, providerLabel, `${providerLabel} panel stayed closed after ${reopenCount} reopen attempts — aborting.`);
        throw new Error(`${providerLabel} panel stayed closed after ${reopenCount} reopen attempts — aborting.`);
      }
      reopenCount++;
      console.error(`INFO: ${providerLabel} panel closed — re-opening to retrieve credentials (attempt ${reopenCount})...`);
      await reopenBtn.click({ force: true }).catch(() => {});
      await page.waitForTimeout(8000);
      continue;
    }
    await page.waitForTimeout(2000);
  }
  await _capturePageDebugState(page, providerLabel, `Timed out after 420000ms waiting for ${providerLabel} credentials to populate.`);
  throw new Error(`Timed out after 420000ms waiting for ${providerLabel} credentials to populate.`);
}

async function _findScopedButton(page, buttonText, providerLabel, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    const allBtns = page.locator(`button:has-text("${buttonText}")`);
    const count = await allBtns.count().catch(() => 0);
    for (let i = 0; i < count; i++) {
      const btn = allBtns.nth(i);
      const visible = await btn.isVisible({ timeout: 300 }).catch(() => false);
      if (!visible) continue;
      const inCard = await btn.evaluate((el, label) => {
        const others = ['AWS', 'Google Cloud', 'GCP', 'Azure'].filter(
          p => !new RegExp(p, 'i').test(label)
        );
        let node = el.parentElement;
        for (let j = 0; j < 8; j++) {
          if (!node) break;
          const t = node.innerText || '';
          if (new RegExp(label, 'i').test(t) && !others.some(p => t.includes(p))) return true;
          node = node.parentElement;
        }
        return false;
      }, providerLabel).catch(() => false);
      if (inCard) return btn;
    }
    if (Date.now() < deadline) await page.waitForTimeout(500);
  }
  return null;
}

async function _closeOpenPanel(page, label) {
  const closeBtn = page.locator(
    'button:has-text("Close"), button[aria-label="close"], button[aria-label="Close"], button[aria-label="Dismiss"]'
  ).first();
  if (await closeBtn.isVisible({ timeout: 1500 }).catch(() => false)) {
    console.error(`INFO: Closing ${label} panel (close button)...`);
    await closeBtn.click({ force: true });
    await page.waitForTimeout(800);
  }
  const stillOpen = await page.locator('input[aria-label="Copyable input"]').isVisible({ timeout: 500 }).catch(() => false);
  if (!stillOpen) return;

  console.error(`INFO: Close button did not dismiss ${label} panel — pressing Escape...`);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(800);
  const stillOpen2 = await page.locator('input[aria-label="Copyable input"]').isVisible({ timeout: 500 }).catch(() => false);
  if (!stillOpen2) return;

  console.error(`INFO: Escape did not dismiss ${label} panel — clicking overlay backdrop...`);
  const size = page.viewportSize();
  await page.mouse.click(size ? Math.floor(size.width * 0.05) : 30, size ? Math.floor(size.height * 0.5) : 300);
  await page.waitForTimeout(800);
}

async function _deleteConflictingSandbox(page, targetProvider) {
  const _providerLabels = { aws: 'AWS', gcp: 'Google Cloud', azure: 'Azure' };
  const targetLabel = _providerLabels[targetProvider] || targetProvider;

  const conflictingLabel = await page.evaluate((tLabel) => {
    // Primary: conflict banner is always visible when another sandbox is running,
    // regardless of whether that provider's panel is open.
    const bodyText = document.body ? (document.body.innerText || '') : '';
    const bannerMatch = bodyText.match(/shut down your current ([A-Za-z ]+?) sandbox/i);
    if (bannerMatch) {
      const label = bannerMatch[1].trim();
      if (!tLabel.toLowerCase().includes(label.toLowerCase())) return label;
    }

    // Fallback: Auto Shutdown text — only present when the provider panel is open.
    const candidates = [
      { label: 'AWS', keywords: ['AWS'] },
      { label: 'Google Cloud', keywords: ['Google Cloud', 'GCP'] },
      { label: 'Azure', keywords: ['Azure'] },
    ].filter(c => !c.keywords.some(k => tLabel.toLowerCase().includes(k.toLowerCase())));

    const allProviderKeywords = ['AWS', 'Google Cloud', 'GCP', 'Azure'];
    for (const c of candidates) {
      const otherKeywords = allProviderKeywords.filter(k => !c.keywords.includes(k));
      const found = Array.from(document.querySelectorAll('*'))
        .some(el => {
          const t = el.innerText || '';
          if (!t.includes('Auto Shutdown')) return false;
          if (!c.keywords.some(k => t.includes(k))) return false;
          // Skip shared containers that mention other providers
          if (otherKeywords.some(k => t.includes(k))) return false;
          return true;
        });
      if (found) return c.label;
    }
    return null;
  }, targetLabel).catch(() => null);

  if (!conflictingLabel) return;

  console.error(`INFO: Running ${conflictingLabel} sandbox detected — deleting before starting ${targetLabel}...`);
  await _closeOpenPanel(page, targetLabel);

  let deleteBtn = await _findScopedButton(page, 'Delete Sandbox', conflictingLabel, 2000);
  if (!deleteBtn) {
    const openConflictBtn = await _findScopedButton(page, 'Open Sandbox', conflictingLabel, 5000);
    if (!openConflictBtn) {
      console.error(`WARN: Could not find Open Sandbox for conflicting ${conflictingLabel} sandbox — proceeding anyway`);
      return;
    }
    await openConflictBtn.click({ force: true });
    deleteBtn = await _findScopedButton(page, 'Delete Sandbox', conflictingLabel, 15000);
  }

  if (!deleteBtn) {
    console.error(`WARN: Delete Sandbox not found for ${conflictingLabel} — proceeding anyway`);
    return;
  }

  await deleteBtn.scrollIntoViewIfNeeded().catch(() => {});
  await deleteBtn.click({ force: true });

  await page.waitForTimeout(1500);
  const confirmBtn = page.locator('[role="alertdialog"] button', { hasText: /delete sandbox/i });
  if (await confirmBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await confirmBtn.click({ force: true });
  }

  console.error(`INFO: Waiting for ${conflictingLabel} sandbox deletion (up to 180s)...`);
  const deleted = await _findScopedButton(page, 'Start Sandbox', conflictingLabel, 180000);
  if (deleted) {
    console.error(`INFO: ${conflictingLabel} sandbox deleted.`);
  } else {
    console.error(`WARN: ${conflictingLabel} sandbox deletion may not be complete — proceeding anyway`);
  }
  await _closeOpenPanel(page, conflictingLabel);
}

async function startSandbox(page, targetUrl, provider) {
  provider = provider || 'aws';
  const _providerLabels = { aws: 'AWS', gcp: 'Google Cloud', azure: 'Azure' };
  const providerLabel = _providerLabels[provider] || provider;

  console.error(`INFO: Looking for ${providerLabel} sandbox buttons...`);
  await page.addLocatorHandler(
    page.locator('h3, h2').filter({ hasText: /sandbox has been extended|session extended/i }).first(),
    async () => {
      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(800);
      // If the toast dismissal closed the credential panel, re-open it
      const inputsVisible = await page.locator('input[aria-label="Copyable input"]').first().isVisible({ timeout: 500 }).catch(() => false);
      if (!inputsVisible) {
        const openBtn = await _findScopedButton(page, 'Open Sandbox', providerLabel, 3000).catch(() => null);
        if (openBtn) {
          console.error('INFO: Credential panel closed after toast dismiss — re-opening...');
          await openBtn.click({ force: true }).catch(() => {});
          await page.waitForTimeout(1000);
        }
      }
    }
  ).catch(() => {});
  await _dismissExtendYourSessionDialog(page);
  let sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  const retryPathname = (() => {
    try { return new URL(targetUrl).pathname; } catch { return ''; }
  })();
  if (!sandboxEntryReady && retryPathname.includes('cloud-sandboxes') && !page.url().includes('cloud-sandboxes')) {
    console.error(`INFO: Sandbox route not active (${page.url()}) — retrying directly via targetUrl...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    const postRetryUrl = page.url();
    if (postRetryUrl.includes('/id') || postRetryUrl.includes('sign-in') || postRetryUrl.includes('login')) {
      await _capturePageDebugState(page, providerLabel, `Sandbox retry redirected to ${postRetryUrl}`);
      throw new Error(`Pluralsight session expired — redirected to ${postRetryUrl}. Re-open or re-create the sandbox and retry.`);
    }
    sandboxEntryReady = await _waitForSandboxEntrySoft(page, 30000);
  }
  await _dismissExtendYourSessionDialog(page);
  if (!sandboxEntryReady) {
    console.error('WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway');
  }

  const credentialsAlreadyVisible = await page.evaluate((pLabel) => {
    const others = ['AWS', 'Google Cloud', 'GCP', 'Azure'].filter(
      p => !new RegExp(p, 'i').test(pLabel)
    );
    const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));
    for (const input of inputs) {
      if (!input.value.trim()) continue;
      let node = input.parentElement;
      for (let j = 0; j < 12; j++) {
        if (!node) break;
        const t = node.innerText || '';
        if (new RegExp(pLabel, 'i').test(t) && !others.some(p => t.includes(p))) return true;
        node = node.parentElement;
      }
    }
    return false;
  }, providerLabel).catch(() => false);

  if (credentialsAlreadyVisible) {
    console.error(`INFO: ${providerLabel} credentials already populated — skipping Start/Open flow`);
    return;
  }

  await _deleteConflictingSandbox(page, provider);

  const startButton = await _findScopedButton(page, 'Start Sandbox', providerLabel, 5000);
  const openButton = await _findScopedButton(page, 'Open Sandbox', providerLabel, 5000);
  const resumeButton = await _findScopedButton(page, 'Resume', providerLabel, 5000);

  if (startButton) {
    const startEnabled = await startButton.isEnabled({ timeout: 1000 }).catch(() => false);
    if (startEnabled) {
      console.error('INFO: Clicking Start Sandbox...');
      await startButton.scrollIntoViewIfNeeded().catch(() => {});
      await startButton.click({ force: true });
    } else {
      const conflictBanner = await page.evaluate(() => {
        const t = document.body ? (document.body.innerText || '') : '';
        return t.includes('You may have only one active sandbox at a time');
      }).catch(() => false);
      if (conflictBanner) {
        console.error('INFO: Start Sandbox disabled due to active conflict — deleting conflicting sandbox...');
        await _deleteConflictingSandbox(page, provider);
        const retryStart = await _findScopedButton(page, 'Start Sandbox', providerLabel, 10000);
        if (retryStart && await retryStart.isEnabled({ timeout: 1000 }).catch(() => false)) {
          await retryStart.scrollIntoViewIfNeeded().catch(() => {});
          await retryStart.click({ force: true });
        }
      } else {
        console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
      }
    }
    await _waitForCredentials(page, providerLabel);
  } else if (openButton) {
    console.error('INFO: Clicking Open Sandbox...');
    await openButton.click({ force: true });
    await page.waitForTimeout(3000);

    const conflictWarningText = await page.evaluate(() => {
      const el = Array.from(document.querySelectorAll('*'))
        .find(el => (el.innerText || '').includes('You may have only one active sandbox at a time'));
      return el ? (el.innerText || '') : '';
    }).catch(() => '');
    if (conflictWarningText) {
      const _conflictMatch = conflictWarningText.match(/shut down your current ([A-Za-z ]+?) sandbox/i);
      const _conflictingProvider = _conflictMatch ? _conflictMatch[1].trim() : null;
      console.error(`WARN: Conflict warning detected — conflicting provider: ${_conflictingProvider || 'unknown'}`);
      await _closeOpenPanel(page, providerLabel);
      if (_conflictingProvider) {
        let _conflictDeleteBtn = await _findScopedButton(page, 'Delete Sandbox', _conflictingProvider, 2000);
        if (!_conflictDeleteBtn) {
          const _conflictOpenBtn = await _findScopedButton(page, 'Open Sandbox', _conflictingProvider, 5000);
          if (_conflictOpenBtn) {
            await _conflictOpenBtn.click({ force: true });
            _conflictDeleteBtn = await _findScopedButton(page, 'Delete Sandbox', _conflictingProvider, 15000);
          }
        }
        if (_conflictDeleteBtn) {
          await _conflictDeleteBtn.scrollIntoViewIfNeeded().catch(() => {});
          await _conflictDeleteBtn.click({ force: true });
          await page.waitForTimeout(1500);
          const _conflictConfirm = page.locator('[role="alertdialog"] button', { hasText: /delete sandbox/i });
          if (await _conflictConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
            await _conflictConfirm.click({ force: true });
          }
          console.error(`INFO: Waiting for ${_conflictingProvider} sandbox deletion (up to 180s)...`);
          await _findScopedButton(page, 'Start Sandbox', _conflictingProvider, 180000);
          await _closeOpenPanel(page, _conflictingProvider);
        } else {
          console.error(`WARN: Could not find Delete Sandbox for ${_conflictingProvider} — proceeding anyway`);
        }
      }
      const retryOpen = await _findScopedButton(page, 'Open Sandbox', providerLabel, 10000);
      if (retryOpen) {
        await retryOpen.click({ force: true });
        await page.waitForTimeout(3000);
      }
    }

    let startButton2 = await _findScopedButton(page, 'Start Sandbox', providerLabel, 30000);
    if (!startButton2) {
      console.error(`WARN: Scoped Start Sandbox not found for ${providerLabel} — trying provider-scoped fallback...`);
      const allStart = page.locator('button:has-text("Start Sandbox")');
      const count = await allStart.count().catch(() => 0);
      const _fbOthers = ['AWS', 'Google Cloud', 'GCP', 'Azure'].filter(p => !new RegExp(p, 'i').test(providerLabel));
      for (let i = 0; i < count; i++) {
        const btn = allStart.nth(i);
        const visible = await btn.isVisible({ timeout: 300 }).catch(() => false);
        const enabled = await btn.isEnabled({ timeout: 300 }).catch(() => false);
        if (!visible || !enabled) continue;
        const inTargetCard = await btn.evaluate((el, [pLabel, others]) => {
          let node = el.parentElement;
          for (let j = 0; j < 20; j++) {
            if (!node) break;
            const t = node.innerText || '';
            if (new RegExp(pLabel, 'i').test(t) && !others.some(p => t.includes(p))) return true;
            if (new RegExp(pLabel, 'i').test(t) && others.some(p => t.includes(p))) break;
            node = node.parentElement;
          }
          return false;
        }, [providerLabel, _fbOthers]).catch(() => false);
        if (inTargetCard) { startButton2 = btn; break; }
      }
    }
    if (startButton2) {
      const startEnabled2 = await startButton2.isEnabled({ timeout: 1000 }).catch(() => false);
      if (startEnabled2) {
        console.error('INFO: Clicking Start Sandbox (Step 2)...');
        await startButton2.scrollIntoViewIfNeeded().catch(() => {});
        await startButton2.click({ force: true });
      } else {
        console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
      }
    } else {
      console.error(`WARN: No Start Sandbox button found for ${providerLabel} after Open Sandbox — proceeding to credential wait`);
    }
    await _waitForCredentials(page, providerLabel);
  } else if (resumeButton) {
    console.error('INFO: Clicking Resume Sandbox...');
    await resumeButton.scrollIntoViewIfNeeded().catch(() => {});
    await resumeButton.click({ force: true });
    await _waitForCredentials(page, providerLabel);
  }
}

module.exports = {
  findOrCreatePage,
  navigateToSandbox,
  waitForSkeleton,
  handleSignIn,
  startSandbox,
  _findScopedButton,
  _capturePageDebugState,
};
