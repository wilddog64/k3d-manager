const { loginWithPage } = require('../../playwright/lib/pluralsight_login');

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
