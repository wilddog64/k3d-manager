const { chromium } = require('playwright');

/**
 * scripts/playwright/acg_credentials.js
 * 
 * Static Playwright script to extract AWS credentials from Pluralsight Cloud Sandbox.
 * Connects to a running Antigravity instance via CDP.
 */

async function extractCredentials() {
  const targetUrl = process.argv[2];
  if (!targetUrl) {
    console.error('ERROR: No target URL provided');
    process.exit(1);
  }

  let browser;
  try {
    // 1. Connect to the running Antigravity browser via CDP
    browser = await chromium.connectOverCDP('http://localhost:9222');

    // 2. Use the first browser context and page
    const context = browser.contexts()[0];
    if (!context) throw new Error('No browser context found');
    const page = context.pages()[0];
    if (!page) throw new Error('No page found in the first browser context');

    console.error(`INFO: Navigating to ${targetUrl}...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    
    // Give it time to render the SPA content
    await page.waitForTimeout(5000);

    // Check if we are on the listing page or a specific sandbox
    const isListingPage = targetUrl.includes('/hands-on/playground/cloud-sandboxes') || targetUrl.endsWith('/cloud-sandboxes');

    if (isListingPage) {
      console.error('INFO: On listing page. Looking for AWS Sandbox...');
      
      // Look for the AWS sandbox card and its start button
      // Based on common Pluralsight patterns: buttons inside a card or grid
      const startButtonSelector = 'button:has-text("Start"), button:has-text("Resume"), button:has-text("Open")';
      
      try {
        // Find all buttons and pick the one related to AWS if multiple exist
        const buttons = await page.locator(startButtonSelector).all();
        let targetButton;
        
        for (const btn of buttons) {
          const text = await btn.innerText();
          const parentText = await btn.evaluate(el => el.closest('div')?.innerText || '');
          if (parentText.toLowerCase().includes('aws')) {
            targetButton = btn;
            break;
          }
        }
        
        if (!targetButton && buttons.length > 0) {
          targetButton = buttons[0]; // Fallback to first start button
        }

        if (targetButton) {
          console.error('INFO: Clicking Start/Open button...');
          await targetButton.click();
          // Wait for navigation or panel to open
          await page.waitForTimeout(10000);
        } else {
          throw new Error('Could not find a Start/Open button for AWS Sandbox');
        }
      } catch (e) {
        console.error(`ERROR: Failed to handle listing page: ${e.message}`);
        process.exit(1);
      }
    }

    // 3. Extract credentials
    console.error('INFO: Extracting credentials...');
    
    // Try multiple selector patterns for the credentials
    const credentialSelectors = {
      accessKey: [
        '[data-testid="access-key-id"]',
        'input[aria-label*="Access Key"]',
        'div:has-text("Access Key ID") + div',
        '.credential-value'
      ],
      secretKey: [
        '[data-testid="secret-access-key"]',
        'input[aria-label*="Secret Key"]',
        'div:has-text("Secret Access Key") + div'
      ],
      sessionToken: [
        '[data-testid="session-token"]',
        'input[aria-label*="Session Token"]',
        'div:has-text("Session Token") + div'
      ]
    };

    async function findValue(selectors) {
      for (const selector of selectors) {
        try {
          const el = page.locator(selector).first();
          if (await el.isVisible()) {
            // Check if it's an input/textarea or a text element
            const tagName = await el.evaluate(node => node.tagName);
            if (tagName === 'INPUT' || tagName === 'TEXTAREA') {
              return await el.inputValue();
            }
            return await el.innerText();
          }
        } catch (e) {}
      }
      return null;
    }

    // Attempt to open the "Cloud Access" or "Credentials" panel if it's closed
    const panelButton = page.locator('button:has-text("Cloud Access"), button:has-text("Credentials"), button:has-text("View Credentials")');
    if (await panelButton.isVisible()) {
      await panelButton.click();
      await page.waitForTimeout(2000);
    }

    const accessKey = await findValue(credentialSelectors.accessKey);
    const secretKey = await findValue(credentialSelectors.secretKey);
    const sessionToken = await findValue(credentialSelectors.sessionToken);

    if (accessKey && secretKey && sessionToken) {
      console.log(`AWS_ACCESS_KEY_ID=${accessKey.trim()}`);
      console.log(`AWS_SECRET_ACCESS_KEY=${secretKey.trim()}`);
      console.log(`AWS_SESSION_TOKEN=${sessionToken.trim()}`);
      process.exit(0);
    } else {
      // Last ditch: check all code blocks
      const codeBlocks = await page.locator('code, pre').all();
      for (const block of codeBlocks) {
        const text = await block.innerText();
        if (text.includes('AWS_ACCESS_KEY_ID')) {
          const ak = text.match(/AWS_ACCESS_KEY_ID=([^\s]+)/)?.[1];
          const sk = text.match(/AWS_SECRET_ACCESS_KEY=([^\s]+)/)?.[1];
          const st = text.match(/AWS_SESSION_TOKEN=([^\s]+)/)?.[1];
          if (ak && sk && st) {
            console.log(`AWS_ACCESS_KEY_ID=${ak}`);
            console.log(`AWS_SECRET_ACCESS_KEY=${sk}`);
            console.log(`AWS_SESSION_TOKEN=${st}`);
            process.exit(0);
          }
        }
      }
      
      throw new Error('Could not find all AWS credential values');
    }

  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  } finally {
    if (browser) await browser.close();
  }
}

extractCredentials();
