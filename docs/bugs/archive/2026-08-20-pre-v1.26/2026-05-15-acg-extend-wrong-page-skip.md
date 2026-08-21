# Bugfix: acg_extend skips navigation when browser is on wrong Pluralsight page

**Branch:** `k3d-manager-v1.4.5`
**File:** `scripts/lib/acg/playwright/acg_extend.js`

---

## Before You Start

1. `git pull origin k3d-manager-v1.4.5`
2. Read this spec in full before touching any file
3. Read `scripts/lib/acg/playwright/acg_extend.js` — confirm the `isPluralsight` block exists

**Branch (work repo):** `k3d-manager-v1.4.5`

---

## Problem

`acg_extend.js` skips navigation to the sandbox URL if the CDP-attached browser is
already on **any** Pluralsight page. The check is:

```javascript
isPluralsight = parsedUrl.hostname === 'pluralsight.com' || parsedUrl.hostname.endsWith('.pluralsight.com');
if (isPluralsight) {
  console.error(`INFO: Already on Pluralsight page: ${currentUrl}`);
} else {
  await page.goto(targetUrl, ...);
}
```

When the browser is on a Pluralsight library or domain page (e.g.
`/library/domain/b499c05b-...` — the AI content page), the script logs
`"Already on Pluralsight page"` and skips navigation. It then looks for the
extend button on the wrong page, finds nothing, and fails.

**Reproduction:** The failure screenshot
`acg-extend-failure-*-missing_extend_button.png` shows the browser on the
Pluralsight AI library page, not the sandboxes page.

---

## Fix

Replace the `isPluralsight` navigation skip with a check that only skips if
the browser is already on the **exact sandbox management path**.

**Old (lines ~138–145 of `acg_extend.js`):**

```javascript
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
```

**New:**

```javascript
    const currentUrl = page.url();
    const isOnSandboxPage = currentUrl.includes('hands-on/playground/cloud-sandboxes') ||
                            currentUrl.includes('cloud-playground/cloud-sandboxes');
    if (isOnSandboxPage) {
      console.error(`INFO: Already on sandbox page: ${currentUrl}`);
    } else {
      console.error(`INFO: Navigating to ${targetUrl} (currently on: ${currentUrl})...`);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    }
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_extend.js` | Replace `isPluralsight` skip with `isOnSandboxPage` check |

---

## What NOT to Do

- Do NOT create a PR — this branch will get its own PR later
- Do NOT skip pre-commit hooks — run hooks normally
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_extend.js`
- Do NOT commit to `main` — work only on `k3d-manager-v1.4.5`

---

## Rules

- Commit on `k3d-manager-v1.4.5`
- Push to `origin/k3d-manager-v1.4.5`

**Commit message (exact):**
```
fix(acg): navigate to sandbox page unconditionally unless already on the sandbox URL
```

---

## Definition of Done

- [ ] `acg_extend.js` no longer contains `isPluralsight` variable
- [ ] Navigation is skipped only when `currentUrl` contains `hands-on/playground/cloud-sandboxes` or `cloud-playground/cloud-sandboxes`
- [ ] Committed and pushed to `origin/k3d-manager-v1.4.5`
- [ ] Commit SHA verified on `origin/k3d-manager-v1.4.5`
