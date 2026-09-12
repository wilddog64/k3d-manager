const { loginWithPage, pageLooksLoggedIn } = require('../../playwright/lib/pluralsight_login');

function makeLocator(visible) {
  return {
    click: jest.fn().mockResolvedValue(undefined),
    fill: jest.fn().mockResolvedValue(undefined),
    first: jest.fn().mockReturnThis(),
    isVisible: jest.fn().mockResolvedValue(visible),
  };
}

function makePage({ mfaVisible = false, loggedInVisible = false } = {}) {
  let currentUrl = 'https://app.pluralsight.com/id/signin';
  const locators = new Map();

  return {
    goto: jest.fn(async (url) => {
      currentUrl = url;
    }),
    locator: jest.fn((selector) => {
      if (!locators.has(selector)) {
        const isLoggedInSelector = selector.includes('Cloud Sandboxes') || selector.includes('Open Sandbox');
        const isMfaSelector = selector.includes('one-time-code') || selector.includes('verification code') || selector.includes('two-?factor') || selector.includes('enter the code');
        locators.set(selector, makeLocator(isMfaSelector ? mfaVisible : isLoggedInSelector ? loggedInVisible : true));
      }
      return locators.get(selector);
    }),
    url: jest.fn(() => currentUrl),
    waitForLoadState: jest.fn().mockResolvedValue(undefined),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
  };
}

describe('pluralsight login helper', () => {
  test('MFA signal present returns failure without solving', async () => {
    const page = makePage({ mfaVisible: true, loggedInVisible: false });

    const result = await loginWithPage(page, 'user@example.com', 'secret');

    expect(result).toEqual({ ok: false, reason: 'mfa_required' });
    expect(page.goto).toHaveBeenNthCalledWith(1, 'https://app.pluralsight.com/id/signin', expect.any(Object));
    expect(page.goto).toHaveBeenCalledTimes(1);
  });
});

function makeSlowRenderPage({ loggedInVisibleFromAttempt = 1 } = {}) {
  let renderAttempt = 0;
  const locators = new Map();
  return {
    goto: jest.fn().mockResolvedValue(undefined),
    locator: jest.fn((selector) => {
      const isLoggedInSelector = selector.includes('Cloud Sandboxes') || selector.includes('Open Sandbox');
      if (!locators.has(selector)) {
        locators.set(selector, {
          first: jest.fn().mockReturnThis(),
          isVisible: jest.fn(async () => isLoggedInSelector && renderAttempt >= loggedInVisibleFromAttempt),
        });
      }
      return locators.get(selector);
    }),
    url: jest.fn(() => 'https://app.pluralsight.com/hands-on/playground/cloud-sandboxes'),
    waitForLoadState: jest.fn(async () => { renderAttempt += 1; }),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
  };
}

describe('pageLooksLoggedIn render-race hardening', () => {
  test('single attempt misses a slow-rendering logged-in page (reproduces the false negative)', async () => {
    const page = makeSlowRenderPage({ loggedInVisibleFromAttempt: 1 });
    const result = await pageLooksLoggedIn(page, { attempts: 1, settleMs: 0 });
    expect(result).toBe(false);
  });

  test('retrying across settle waits detects the logged-in page once it renders', async () => {
    const page = makeSlowRenderPage({ loggedInVisibleFromAttempt: 1 });
    const result = await pageLooksLoggedIn(page, { attempts: 4, settleMs: 0 });
    expect(result).toBe(true);
    expect(page.waitForLoadState).toHaveBeenCalled();
  });
});
