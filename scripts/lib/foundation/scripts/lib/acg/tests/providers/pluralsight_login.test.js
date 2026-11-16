const {
  loginWithPage,
  pageLooksLoggedIn,
  LOGGED_IN_SELECTORS,
  SANDBOX_URL,
  EMAIL_SELECTOR,
  PASSWORD_SELECTOR,
  SUBMIT_SELECTOR,
  SIGNED_OUT_SELECTORS,
  urlLooksSignedOut,
} = require('../../playwright/lib/pluralsight_login');
const fs = require('fs');
const os = require('os');
const path = require('path');
const originalXdgStateHome = process.env.XDG_STATE_HOME;
let scratchStateHome;

beforeEach(() => {
  scratchStateHome = fs.mkdtempSync(path.join(os.tmpdir(), 'acg-login-tests-'));
  process.env.XDG_STATE_HOME = scratchStateHome;
});

afterEach(() => {
  if (originalXdgStateHome === undefined) delete process.env.XDG_STATE_HOME;
  else process.env.XDG_STATE_HOME = originalXdgStateHome;
  if (scratchStateHome) fs.rmSync(scratchStateHome, { recursive: true, force: true });
  scratchStateHome = undefined;
  jest.restoreAllMocks();
});

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

function makePage({ mfaVisible = false, loggedInVisible = false, passwordVisible = true, emailVisible = true, title = 'Sign in' } = {}) {
  let currentUrl = 'https://app.pluralsight.com/id/signin?token=SENTINEL';
  const locators = new Map();

  return {
    goto: jest.fn(async (url) => {
      currentUrl = url === 'https://app.pluralsight.com/id/signin' ? `${url}?token=SENTINEL` : url;
    }),
    locator: jest.fn((selector) => {
      if (!locators.has(selector)) {
        const isLoggedInSelector = LOGGED_IN_SELECTORS.includes(selector);
        const isSignedOutSelector = SIGNED_OUT_SELECTORS.includes(selector);
        const isMfaSelector = selector.includes('one-time-code') || selector.includes('verification code') || selector.includes('two-?factor') || selector.includes('enter the code');
        const isPasswordSelector = selector === PASSWORD_SELECTOR;
        const isEmailSelector = selector === EMAIL_SELECTOR;
        const loc = makeLocator(isMfaSelector ? mfaVisible : isLoggedInSelector ? loggedInVisible : isSignedOutSelector ? false : isPasswordSelector ? passwordVisible : isEmailSelector ? emailVisible : true);
        loc.count = jest.fn().mockResolvedValue(isPasswordSelector ? Number(passwordVisible) : isEmailSelector ? Number(emailVisible) : selector.includes('challenges.cloudflare.com') ? 0 : Number(isLoggedInSelector ? loggedInVisible : true));
        locators.set(selector, loc);
      }
      return locators.get(selector);
    }),
    url: jest.fn(() => currentUrl),
    title: jest.fn().mockResolvedValue(title),
    screenshot: jest.fn().mockResolvedValue(Buffer.from('fake-png')),
    waitForLoadState: jest.fn().mockResolvedValue(undefined),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
  };
}

describe('pluralsight login helper', () => {
  test('diagnostic state is isolated under the temporary directory', () => {
    expect(process.env.XDG_STATE_HOME.startsWith(os.tmpdir())).toBe(true);
  });

  test('relative XDG_STATE_HOME falls back under the home state directory', async () => {
    const home = path.join(scratchStateHome, 'home');
    fs.mkdirSync(home);
    const homeSpy = jest.spyOn(os, 'homedir').mockReturnValue(home);
    process.env.XDG_STATE_HOME = 'relative-state';
    const page = makePage({ emailVisible: false });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    await loginWithPage(page, 'user', 'secret');
    expect(fs.existsSync(path.join(home, '.local', 'state', 'k3d-manager', 'acg-diag'))).toBe(true);
    expect(error).toHaveBeenCalledWith(expect.stringContaining('screenshot='));
    homeSpy.mockRestore();
    error.mockRestore();
  });

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
    const page = makePage({ emailVisible: false });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});

    await expect(loginWithPage(page, 'SENTINEL_USER', 'SENTINEL_PASSWORD')).resolves.toEqual({
      ok: false,
      reason: 'login_form_unavailable',
    });
    expect(page.locator(SUBMIT_SELECTOR).evaluate).not.toHaveBeenCalled();
    const diag = error.mock.calls.map(call => call[0]).find(line => line.startsWith('ACG_LOGIN_DIAG:'));
    expect(diag).toContain('reason=login_form_unavailable');
    expect(diag).toContain('url=https://app.pluralsight.com/id/signin');
    expect(diag).toContain('title="Sign in"');
    expect(diag).toContain('email_matches=0');
    expect(diag).not.toContain('SENTINEL');
    const screenshot = diag.match(/screenshot=(\S+)/)[1];
    expect(fs.existsSync(screenshot)).toBe(true);
    expect(fs.statSync(screenshot).mode & 0o777).toBe(0o600);
    expect(page.screenshot).toHaveBeenCalledTimes(1);
    error.mockRestore();
  });

  test('challenge title is recorded and plain title is not flagged', async () => {
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    for (const [title, challenge] of [['Just a moment...', 'yes'], ['Sign in', 'no']]) {
      const page = makePage({ emailVisible: false, title });
      await loginWithPage(page, 'user@example.com', 'secret');
      const lines = error.mock.calls.map(call => call[0]).filter(text => text.startsWith('ACG_LOGIN_DIAG:'));
      const line = lines[lines.length - 1];
      expect(line).toContain(`challenge=${challenge}`);
    }
    error.mockRestore();
  });

  test('challenge iframe alone flags a plain title', async () => {
    const page = makePage({ emailVisible: false });
    page.locator.mockImplementation(selector => {
      const loc = makeLocator(false);
      loc.count = jest.fn().mockResolvedValue(selector.includes('challenges.cloudflare.com') ? 1 : 0);
      return loc;
    });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    await loginWithPage(page, 'user@example.com', 'secret');
    expect(error.mock.calls.map(call => call[0]).find(line => line.startsWith('ACG_LOGIN_DIAG:'))).toContain('challenge=yes');
    error.mockRestore();
  });

  test('title is safely redacted, quoted, single-line, and limited to 80 characters', async () => {
    const title = 'x "SENTINEL_USER"\n\x1b[31m screenshot=/etc/passwd' + 'z'.repeat(100);
    const page = makePage({ emailVisible: false, title });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    await loginWithPage(page, 'SENTINEL_USER', 'secret');
    const line = error.mock.calls.map(call => call[0]).find(item => item.startsWith('ACG_LOGIN_DIAG:'));
    const quotedTitle = line.match(/title="([^"]*)"/)[1];
    expect(line).not.toContain('SENTINEL_USER');
    expect(line).not.toContain('\x1b');
    expect(line).not.toMatch(/[\r\n]/);
    expect(quotedTitle).toHaveLength(80);
    error.mockRestore();
  });

  test('fill errors do not expose Playwright call logs or credentials', async () => {
    const page = makePage();
    page.locator.mockImplementation(selector => {
      const loc = makeLocator(true);
      loc.fill = jest.fn(async value => {
        if (selector === PASSWORD_SELECTOR && value === 'SENTINEL_PASSWORD') {
          throw new Error('locator.fill: Timeout - fill("SENTINEL_PASSWORD")');
        }
      });
      return loc;
    });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    let thrown;
    try {
      await loginWithPage(page, 'SENTINEL_USER', 'SENTINEL_PASSWORD');
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeDefined();
    expect(thrown.message).not.toContain('SENTINEL');
    expect(error).not.toHaveBeenCalled();
    error.mockRestore();
  });

  test('email filled and password missing emits no screenshot path', async () => {
    const page = makePage({ passwordVisible: false });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    await loginWithPage(page, 'user', 'secret');
    const line = error.mock.calls.map(call => call[0]).find(item => item.startsWith('ACG_LOGIN_DIAG:'));
    expect(line).toContain('email_matches=1');
    expect(line).not.toContain('screenshot=');
    expect(page.screenshot).not.toHaveBeenCalled();
    error.mockRestore();
  });

  test('login_failed emits diagnostics without a screenshot after fields were filled', async () => {
    const page = makePage({ loggedInVisible: false });
    page.goto.mockImplementation(async url => {
      if (url.includes('cloud-sandboxes')) page.url.mockReturnValue(url);
    });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    await expect(loginWithPage(page, 'SENTINEL_USER', 'SENTINEL_PASSWORD')).resolves.toEqual({ ok: false, reason: 'login_failed' });
    const diag = error.mock.calls.map(call => call[0]).find(line => line.startsWith('ACG_LOGIN_DIAG:'));
    expect(diag).toContain('reason=login_failed');
    expect(diag).not.toContain('screenshot=');
    expect(page.screenshot).not.toHaveBeenCalled();
    expect(diag).not.toContain('SENTINEL');
    error.mockRestore();
  });

  test('screenshot failure does not change login result or throw', async () => {
    const page = makePage({ emailVisible: false });
    page.screenshot.mockRejectedValue(new Error('screenshot unavailable'));
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    await expect(loginWithPage(page, 'user', 'secret')).resolves.toEqual({ ok: false, reason: 'login_form_unavailable' });
    expect(error).toHaveBeenCalledWith(expect.stringContaining('screenshot=failed'));
    error.mockRestore();
  });

  test('successful login does not emit diagnostics', async () => {
    const page = makePage({ loggedInVisible: true });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    await loginWithPage(page, 'user', 'secret');
    expect(error.mock.calls.some(call => call[0].startsWith('ACG_LOGIN_DIAG:'))).toBe(false);
    error.mockRestore();
  });

  test('screenshot retention keeps at most five diagnostic images', async () => {
    const page = makePage({ emailVisible: false });
    const error = jest.spyOn(console, 'error').mockImplementation(() => {});
    const reported = [];
    for (let i = 0; i < 7; i += 1) {
      await loginWithPage(page, 'user', 'secret');
      const lines = error.mock.calls.map(call => call[0]).filter(line => line.startsWith('ACG_LOGIN_DIAG:'));
      const file = lines[lines.length - 1].match(/screenshot=(\S+)/)[1];
      reported.push(file);
      fs.utimesSync(file, new Date(1700000000 + i * 60), new Date(1700000000 + i * 60));
    }
    const dir = path.join(scratchStateHome, 'k3d-manager', 'acg-diag');
    const retained = fs.readdirSync(dir).filter(name => name.endsWith('.png')).map(name => path.join(dir, name));
    expect(retained).toHaveLength(5);
    expect(retained.sort()).toEqual(reported.slice(-5).sort());
    expect(fs.existsSync(reported[6])).toBe(true);
    expect(fs.statSync(dir).mode & 0o777).toBe(0o700);
    error.mockRestore();
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
    const diag = error.mock.calls.map(call => call[0]).find(line => line.startsWith('ACG_LOGIN_DIAG:'));
    expect(diag).toContain('email_matches=1');
    expect(diag).not.toContain('screenshot=');
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
