// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');

const FIXTURE_URL = `file://${path.resolve(__dirname, 'fixtures/sandbox.html')}`;

// ── helpers mirroring acg_restart.js logic ────────────────────────────────

// acg_restart.js uses .first() for all listing-page buttons — tests must match
const deleteBtn = (page) => page.locator('button:has-text("Delete Sandbox")').first();
const openBtn   = (page) => page.locator('button:has-text("Open Sandbox")').first();
const startBtn  = (page) => page.locator('button:has-text("Start Sandbox")').first();

async function dismissExtendDialog(page) {
  return page.evaluate(() => {
    const dialog = Array.from(document.querySelectorAll('[role="dialog"]'))
      .find(d => (d.innerText || '').includes('Extend Your Session'));
    if (!dialog) return false;
    const btn = Array.from(dialog.querySelectorAll('button'))
      .find(b => /cancel|no thanks|close|dismiss/i.test(b.textContent || b.getAttribute('aria-label') || ''))
      || Array.from(dialog.querySelectorAll('button'))
        .find(b => !/extend/i.test(b.textContent || ''));
    if (btn) { btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })); return true; }
    return false;
  });
}

async function clickDeleteConfirm(page) {
  return page.evaluate(() => {
    const dialog = document.querySelector('[role="alertdialog"]');
    if (!dialog) return { ok: false, reason: 'no alertdialog' };
    const btns = Array.from(dialog.querySelectorAll('button'));
    const btn = btns.find(b => /delete sandbox/i.test(b.textContent || ''));
    if (!btn) return { ok: false, reason: `buttons: ${btns.map(b => b.textContent.trim()).join(' | ')}` };
    btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    return { ok: true, text: btn.textContent.trim() };
  });
}

// ── tests ─────────────────────────────────────────────────────────────────

test.beforeEach(async ({ page }) => {
  await page.goto(FIXTURE_URL);
});

test('Open Sandbox reveals Delete Sandbox button', async ({ page }) => {
  await expect(openBtn(page)).toBeVisible();
  await openBtn(page).click({ force: true });
  await expect(deleteBtn(page)).toBeVisible();
  await expect(page.locator('#result')).toHaveAttribute('data-state', 'panel-open');
});

test('Delete Sandbox opens alertdialog', async ({ page }) => {
  await openBtn(page).click({ force: true });
  await deleteBtn(page).click({ force: true });
  await expect(page.locator('[role="alertdialog"]')).toBeVisible();
  await expect(page.locator('#result')).toHaveAttribute('data-state', 'confirm-dialog-open');
});

test('dispatchEvent(MouseEvent bubbles:true) dismisses alertdialog and triggers deletion', async ({ page }) => {
  await openBtn(page).click({ force: true });
  await deleteBtn(page).click({ force: true });
  await expect(page.locator('[role="alertdialog"]')).toBeVisible();

  // Exact pattern from acg_restart.js — must trigger the document-delegated listener
  const result = await clickDeleteConfirm(page);
  expect(result.ok).toBe(true);

  // Dialog must disappear
  await expect(page.locator('[role="alertdialog"]')).toBeHidden();

  // Start Sandbox must appear (fixture has 200ms backend-simulation delay)
  await expect(startBtn(page)).toBeVisible({ timeout: 2000 });
  await expect(page.locator('#result')).toHaveAttribute('data-state', 'deleted');
});

test('alertdialog is gone 2s after dispatchEvent click (post-click verification check)', async ({ page }) => {
  await openBtn(page).click({ force: true });
  await deleteBtn(page).click({ force: true });
  await expect(page.locator('[role="alertdialog"]')).toBeVisible();

  await clickDeleteConfirm(page);

  // The 2s post-click alertdialog-still-open check in acg_restart.js must return false
  await page.waitForTimeout(200); // fixture delay
  const dialogStillOpen = await page.evaluate(() =>
    Boolean(document.querySelector('[role="alertdialog"]:not(.hidden)'))
  );
  expect(dialogStillOpen).toBe(false);
});

test('Extend Your Session dialog is dismissed via Cancel (not Extend Session)', async ({ page }) => {
  await page.evaluate(() => window.__showExtendDialog());
  await expect(page.locator('[role="dialog"]:has-text("Extend Your Session")')).toBeVisible();

  const dismissed = await dismissExtendDialog(page);
  expect(dismissed).toBe(true);
  await expect(page.locator('[role="dialog"]:has-text("Extend Your Session")')).toBeHidden();
});

test('fast-path: already-deleted sandbox skips directly to Start Sandbox', async ({ page }) => {
  await page.evaluate(() => window.__setAlreadyDeleted());

  await expect(startBtn(page)).toBeVisible();
  // Scope check to listing-page panel — alertdialog button is in hidden parent but still in DOM
  await expect(page.locator('#state-panel')).toBeHidden();
  await expect(page.locator('#state-card')).toBeHidden();

  await startBtn(page).click({ force: true });
  await expect(page.locator('#result')).toHaveAttribute('data-state', 'started');
});

test('selector role=alertdialog is distinct from role=dialog', async ({ page }) => {
  await openBtn(page).click({ force: true });
  await deleteBtn(page).click({ force: true });
  await page.evaluate(() => window.__showExtendDialog());

  const alertDialogCount = await page.locator('[role="alertdialog"]').count();
  const dialogCount = await page.locator('[role="dialog"]').count();

  expect(alertDialogCount).toBe(1);
  expect(dialogCount).toBe(1);

  await expect(page.locator('[role="alertdialog"]')).toContainText('Delete AWS Sandbox');
  await expect(page.locator('[role="dialog"]')).toContainText('Extend Your Session');
});
