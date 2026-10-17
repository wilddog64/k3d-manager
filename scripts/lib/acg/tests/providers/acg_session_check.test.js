jest.mock('../../playwright/lib/pluralsight_login', () => ({
  SANDBOX_URL: 'https://sandbox.example',
  SIGNIN_URL: 'https://signin.example',
  loginWithPage: jest.fn(),
  pageLooksLoggedIn: jest.fn(),
}));

jest.mock('playwright', () => ({
  chromium: {
    connectOverCDP: jest.fn(),
  },
}));

const { chromium } = require('playwright');
const loginLib = require('../../playwright/lib/pluralsight_login');
const sessionCheck = require('../../acg_session_check');

function makePage() {
  let currentUrl = 'https://signin.example';
  return {
    goto: jest.fn(async (url) => {
      currentUrl = url;
    }),
    url: jest.fn(() => currentUrl),
    waitForLoadState: jest.fn().mockResolvedValue(undefined),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
  };
}

describe('acg_session_check', () => {
  const originalEnv = process.env;
  const originalIsTTY = process.stdout.isTTY;

  let browser;
  let context;
  let page;

  beforeEach(() => {
    jest.resetAllMocks();
    process.env = { ...originalEnv };
    page = makePage();
    context = {
      newPage: jest.fn().mockResolvedValue(page),
      pages: jest.fn(() => [page]),
    };
    browser = {
      close: jest.fn().mockResolvedValue(undefined),
      contexts: jest.fn(() => [context]),
    };
    chromium.connectOverCDP.mockResolvedValue(browser);
    loginLib.pageLooksLoggedIn.mockResolvedValue(false);
    loginLib.loginWithPage.mockResolvedValue({ ok: false, reason: 'login_failed' });
    process.stdout.isTTY = true;
  });

  afterAll(() => {
    process.env = originalEnv;
    process.stdout.isTTY = originalIsTTY;
  });

  test('no creds skips auto-login and fails fast without polling', async () => {
    delete process.env.ACG_USERNAME;
    delete process.env.ACG_PASSWORD;
    process.env.K3DM_NONINTERACTIVE = '1';

    await expect(sessionCheck._main()).rejects.toThrow('ACG_SESSION_EXPIRED');

    expect(loginLib.loginWithPage).not.toHaveBeenCalled();
    expect(page.waitForTimeout).not.toHaveBeenCalled();
    expect(browser.close).toHaveBeenCalled();
  });

  test('noninteractive MFA-required session fails fast without polling', async () => {
    process.env.ACG_USERNAME = 'ci@example.com';
    process.env.ACG_PASSWORD = 'secret';
    process.env.K3DM_NONINTERACTIVE = '1';
    loginLib.loginWithPage.mockResolvedValue({ ok: false, reason: 'mfa_required' });

    await expect(sessionCheck._main()).rejects.toThrow('ACG_SESSION_EXPIRED');

    expect(loginLib.loginWithPage).toHaveBeenCalled();
    expect(page.waitForTimeout).not.toHaveBeenCalled();
    expect(browser.close).toHaveBeenCalled();
  });

  test('credential state distinguishes absent, empty, and present', () => {
    expect(sessionCheck._credentialState(undefined)).toBe('absent');
    expect(sessionCheck._credentialState('')).toBe('empty');
    expect(sessionCheck._credentialState('configured')).toBe('present');
  });

  test('existing session reports credential state and path', async () => {
    delete process.env.ACG_USERNAME;
    delete process.env.ACG_PASSWORD;
    loginLib.pageLooksLoggedIn.mockResolvedValue(true);
    const stdoutWrite = jest.spyOn(process.stdout, 'write').mockImplementation(() => true);
    const stderrError = jest.spyOn(console, 'error').mockImplementation(() => {});

    await sessionCheck._main();

    expect(stderrError).toHaveBeenCalledWith('ACG_CREDENTIALS: username=absent password=absent');
    expect(stdoutWrite).toHaveBeenCalledWith('ACG_SESSION_OK path=existing-session\n');
    stdoutWrite.mockRestore();
    stderrError.mockRestore();
  });

  test('required credentials rejects an authenticated session with an empty password', async () => {
    process.env.ACG_USERNAME = 'configured';
    process.env.ACG_PASSWORD = '';
    process.env.K3DM_ACG_REQUIRE_CREDENTIALS = '1';
    loginLib.pageLooksLoggedIn.mockResolvedValue(true);
    const stderrError = jest.spyOn(console, 'error').mockImplementation(() => {});

    await expect(sessionCheck._main()).rejects.toThrow('ACG_CREDENTIALS_REQUIRED');

    expect(stderrError).toHaveBeenCalledWith(expect.stringContaining('ACG_CREDENTIALS_REQUIRED'));
    expect(stderrError).toHaveBeenCalledWith(expect.stringContaining('password=empty'));
    expect(stderrError).not.toHaveBeenCalledWith(expect.stringContaining('ACG_SESSION_EXPIRED'));
    stderrError.mockRestore();
  });

  test('unset credential requirement preserves authenticated-session success', async () => {
    process.env.ACG_USERNAME = 'configured';
    process.env.ACG_PASSWORD = '';
    delete process.env.K3DM_ACG_REQUIRE_CREDENTIALS;
    loginLib.pageLooksLoggedIn.mockResolvedValue(true);
    const stdoutWrite = jest.spyOn(process.stdout, 'write').mockImplementation(() => true);
    const stderrError = jest.spyOn(console, 'error').mockImplementation(() => {});

    await sessionCheck._main();

    expect(stdoutWrite).toHaveBeenCalledWith('ACG_SESSION_OK path=existing-session\n');
    expect(stderrError).toHaveBeenCalledWith('ACG_CREDENTIALS: username=present password=empty');
    stdoutWrite.mockRestore();
    stderrError.mockRestore();
  });
});
