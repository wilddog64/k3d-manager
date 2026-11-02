const {
  loginWithPage,
  pageLooksLoggedIn,
  SANDBOX_URL,
  EMAIL_SELECTOR,
  PASSWORD_SELECTOR,
  SUBMIT_SELECTOR,
  SIGNED_OUT_SELECTORS,
  urlLooksSignedOut,
} = require('../../playwright/lib/pluralsight_login');

function makeLocator(visible) {
  return {
    click: jest.fn().mockResolvedValue(undefined),
    evaluate: jest.fn().mockResolvedValue(undefined),
    fill: jest.fn().mockResolvedValue(undefined),
    first: jest.fn().mockReturnThis(),
    isVisible: jest.fn().mockResolvedValue(visible),
    waitFor: jest.fn(async () => {
      if (!visible) {
        throw new Error('not visible');
      }
    }),
  };
}

function makePage({ mfaVisible = false, loggedInVisible = false, passwordVisible = true } = {}) {
  let currentUrl = 'https://app.pluralsight.com/id/signin';
  const locators = new Map();

  return {
    goto: jest.fn(async (url) => {
      currentUrl = url;
    }),
    locator: jest.fn((selector) => {
      if (!locators.has(selector)) {
        const isLoggedInSelector = selector.includes('psPrismMonogram');
        const isSignedOutSelector = SIGNED_OUT_SELECTORS.includes(selector);
        const isMfaSelector = selector.includes('one-time-code') || selector.includes('verification code') || selector.includes('two-?factor') || selector.includes('enter the code');
        const isPasswordSelector = selector === PASSWORD_SELECTOR;
        locators.set(selector, makeLocator(isMfaSelector ? mfaVisible : isLoggedInSelector ? loggedInVisible : isSignedOutSelector ? false : isPasswordSelector ? passwordVisible : true));
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

  test('fillIfVisible no longer clicks the fields', async () => {
    const page = makePage({ loggedInVisible: true });

    await loginWithPage(page, 'user@example.com', 'secret');

    expect(page.locator(EMAIL_SELECTOR).click).not.toHaveBeenCalled();
    expect(page.locator(PASSWORD_SELECTOR).click).not.toHaveBeenCalled();
    expect(page.locator(EMAIL_SELECTOR).fill).toHaveBeenCalled();
    expect(page.locator(PASSWORD_SELECTOR).fill).toHaveBeenCalled();
  });

  test('a field that never becomes visible returns login_form_unavailable', async () => {
    const page = makePage({ passwordVisible: false });

    await expect(loginWithPage(page, 'user@example.com', 'secret')).resolves.toEqual({
      ok: false,
      reason: 'login_form_unavailable',
    });
    expect(page.locator(SUBMIT_SELECTOR).evaluate).not.toHaveBeenCalled();
  });

  test('submit is dispatched, not clicked', async () => {
    const page = makePage({ loggedInVisible: true });

    await loginWithPage(page, 'user@example.com', 'secret');

    expect(page.locator(SUBMIT_SELECTOR).evaluate).toHaveBeenCalled();
    expect(page.locator(SUBMIT_SELECTOR).click).not.toHaveBeenCalled();
  });

  test('the submit wait carries an explicit timeout, not Playwright default', async () => {
    const page = makePage({ loggedInVisible: true });

    await loginWithPage(page, 'user@example.com', 'secret');

    expect(page.locator(SUBMIT_SELECTOR).waitFor).toHaveBeenCalledWith(
      expect.objectContaining({ state: 'visible', timeout: expect.any(Number) }),
    );
  });

  test('the missing-field log line leaks no credential', async () => {
    const page = makePage({ passwordVisible: false });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});

    await loginWithPage(page, 'user@example.com', 'secret');

    expect(error).toHaveBeenCalledWith(expect.stringContaining('ACG_LOGIN_FIELDS_MISSING'));
    expect(error.mock.calls[0][0]).not.toContain('secret');
    error.mockRestore();
  });
});

function makeSlowRenderPage({ loggedInVisibleFromAttempt = 1 } = {}) {
  let renderAttempt = 0;
  const locators = new Map();
  return {
    goto: jest.fn().mockResolvedValue(undefined),
    locator: jest.fn((selector) => {
      const isLoggedInSelector = selector.includes('psPrismMonogram');
      const isSignedOutSelector = SIGNED_OUT_SELECTORS.includes(selector);
      if (!locators.has(selector)) {
        locators.set(selector, {
          first: jest.fn().mockReturnThis(),
          isVisible: jest.fn(async () => !isSignedOutSelector && isLoggedInSelector && renderAttempt >= loggedInVisibleFromAttempt),
        });
      }
      return locators.get(selector);
    }),
    url: jest.fn(() => 'https://app.pluralsight.com/hands-on/playground/cloud-sandboxes'),
    waitForLoadState: jest.fn(async () => { renderAttempt += 1; }),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
  };
}

describe('EMAIL_SELECTOR case sensitivity', () => {
  // Pluralsight serves name="Username" (PascalCase) on a type="text" input. CSS attribute
  // values are case-sensitive, so the old lowercase arms matched nothing and the email field
  // was silently reported missing while the form was fully visible. jest has no DOM here
  // (the suite is offline, no jsdom), so this guards the selector's shape; the behavioral
  // proof is the live Playwright probe recorded in the bug doc: count 0 -> 1.
  test('no bare case-sensitive name arm survives', () => {
    expect(EMAIL_SELECTOR).not.toMatch(/\[name="username"\]/);
    expect(EMAIL_SELECTOR).not.toMatch(/\[name="email"\]/);
  });

  test('username and email arms are case-insensitive', () => {
    expect(EMAIL_SELECTOR).toMatch(/\[name="username" i\]/);
    expect(EMAIL_SELECTOR).toMatch(/\[name="email" i\]/);
  });

  test('every name and id arm carries the case-insensitivity flag', () => {
    const arms = EMAIL_SELECTOR.split(',').map((arm) => arm.trim());
    const attrArms = arms.filter((arm) => /\[(name|id)=/.test(arm));
    expect(attrArms.length).toBeGreaterThan(0);
    for (const arm of attrArms) {
      expect(arm).toMatch(/ i\]$/);
    }
  });
});

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

describe('pageLooksLoggedIn signed-out detection', () => {
  test('Cloud Sandboxes content alone does not indicate an authenticated session', async () => {
    const page = {
      locator: jest.fn((selector) => makeLocator(selector.includes('Cloud Sandboxes'))),
      url: jest.fn(() => SANDBOX_URL),
    };

    await expect(pageLooksLoggedIn(page)).resolves.toBe(false);
  });

  test('visible Sign in marker short-circuits without retrying', async () => {
    const page = {
      locator: jest.fn((selector) => makeLocator(selector.includes('has-text("Sign in")'))),
      url: jest.fn(() => SANDBOX_URL),
      waitForLoadState: jest.fn().mockResolvedValue(undefined),
      waitForTimeout: jest.fn().mockResolvedValue(undefined),
    };

    await expect(pageLooksLoggedIn(page, { attempts: 4, settleMs: 0 })).resolves.toBe(false);
    expect(page.waitForLoadState).not.toHaveBeenCalled();
  });

  test('recognizes Pluralsight identity URLs as signed out', () => {
    expect(urlLooksSignedOut('https://app.pluralsight.com/id')).toBe(true);
    expect(urlLooksSignedOut('https://app.pluralsight.com/id/signin')).toBe(true);
    expect(urlLooksSignedOut(SANDBOX_URL)).toBe(false);
    expect(urlLooksSignedOut('https://app.pluralsight.com/identity-docs')).toBe(false);
  });
});
