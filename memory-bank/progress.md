## Done: Attempted to extend sandbox TTL

### ag_acg_extend.js

```javascript
const { chromium } = require('playwright');

(async () => {
  let browser;
  try {
    // 1. Connect to the running Antigravity browser via CDP
    browser = await chromium.connectOverCDP('http://localhost:9222');

    // 2. Use the first browser context and page
    const contexts = browser.contexts();
    if (contexts.length === 0) {
      console.error('Error: No browser contexts found. Ensure a browser is running.');
      process.exit(1);
    }
    const page = contexts[0].pages()[0];
    if (!page) {
      console.error('Error: No page found in the first browser context. Ensure a page is open.');
      process.exit(1);
    }

    // 3. Call await page.goto('https://app.pluralsight.com/cloud-playground/cloud-sandboxes', {waitUntil: 'networkidle'}) unconditionally
    console.log('Navigating to sandbox page...');
    await page.goto('https://app.pluralsight.com/cloud-playground/cloud-sandboxes', { waitUntil: 'domcontentloaded' });
    await page.waitForLoadState('domcontentloaded');
    console.log('Navigation complete.');

    // 4. Find the sandbox TTL extend button (look for 'Extend', '+4 hours', or similar)
    // 5. Click to extend by 4 hours.
    console.log('Searching for extend button...');
    const extendButton = await page.getByRole('button', { name: /Extend|\+4 hours/i }).first();
    
    if (!(await extendButton.isVisible())) {
      console.error('Error: Extend button not found or not visible.');
      process.exit(1);
    }

    console.log('Clicking extend button...');
    await extendButton.click();
    console.log('Extend button clicked. Waiting for confirmation...');

    // 6. Confirm the new TTL is shown on the page.
    // Wait for the confirmation message or the updated expiry time to appear.
    // This is a heuristic: we'll look for text indicating a new expiry or an updated time.
    await page.getByText(/(expires in|extended until)/i, { timeout: 10000 }).catch(() => {
        console.error('Error: Could not confirm TTL extension message.');
        process.exit(1);
    });
    console.log('TTL extension confirmed on page.');

    // 7. Print the new sandbox expiry time.
    // Try to find an element that contains the expiry time.
    const expiryTimeElement = await page.getByText(/(expires in|extended until)/i).first();    if (await expiryTimeElement.isVisible()) {
      const expiryText = await expiryTimeElement.textContent();
      console.log(`New Sandbox Expiry Time: ${expiryText.trim()}`);
    } else {
      console.log('Could not find specific element displaying the new expiry time. Extension likely successful.');
    }

  } catch (error) {
    console.error(`An unexpected error occurred: ${error.message}`);
    process.exit(1);
  } finally {
    if (browser) {
      // In a real scenario, we might close the browser or context if we opened it.
      // Since we are connecting to an existing one, we don't close it here.
    }
  }
})();
```

### Execution Output
```
Output: Navigating to sandbox page...
Navigation complete.
Searching for extend button...
Error: Extend button not found or not visible.
Exit Code: 1
Process Group PGID: 39103
```

### Notes
The Playwright script was executed but failed to find the "Extend" button or any element containing the text "+4 hours" on the target page. Multiple attempts were made to refine the locator strategy, including using `page.locator` with `has-text`, `page.getByRole`, and `page.getByText` with regular expressions. The issue seems to stem from the button genuinely not being present or visible in the observed page state. Without further information about the dynamic nature of the page or a direct inspection of its DOM, the script cannot proceed to click the button and confirm the TTL extension.
