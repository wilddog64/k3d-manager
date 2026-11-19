const {
  navigateToSandbox,
  handleSignIn,
  _sandboxNavigationCandidates,
  _isStalePluralsightRoute,
} = require('../../playwright/lib/sandbox');

function makePage(initialUrl, staleFirstRoute = false) {
  let currentUrl = initialUrl;
  return {
    locator: jest.fn(() => ({
      first: jest.fn().mockReturnValue({
        isVisible: jest.fn().mockResolvedValue(false),
      }),
    })),
    goto: jest.fn(async (url) => {
      currentUrl = staleFirstRoute && url.includes('/hands-on/')
        ? 'https://s2.pluralsight.com/404.html'
        : url;
    }),
    url: jest.fn(() => currentUrl),
  };
}

function makeSignInPage() {
  const signInLink = {
    isVisible: jest.fn().mockResolvedValue(true),
    click: jest.fn(),
  };
  const emailInput = {
    isVisible: jest.fn().mockResolvedValue(false),
    waitFor: jest.fn(),
    click: jest.fn(),
    fill: jest.fn(),
  };
  const hiddenControl = {
    isVisible: jest.fn().mockResolvedValue(false),
    click: jest.fn(),
  };
  const page = {
    locator: jest.fn((selector) => ({
      first: jest.fn().mockReturnValue(
        selector.startsWith('a[href*="/id/signin"]') ? signInLink
          : selector.includes('input[type="email"]') ? emailInput
            : hiddenControl
      ),
    })),
    waitForURL: jest.fn(),
    waitForFunction: jest.fn().mockResolvedValue(undefined),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
  };
  return { page, signInLink };
}

describe('sandbox page routing', () => {
  test('recognizes the s2 404 route as stale', () => {
    expect(_isStalePluralsightRoute('https://s2.pluralsight.com/404.html')).toBe(true);
    expect(_isStalePluralsightRoute('https://app.pluralsight.com/hands-on/playground/cloud-sandboxes')).toBe(false);
  });

  test('adds the legacy sandbox route as a recovery candidate', () => {
    expect(_sandboxNavigationCandidates('https://app.pluralsight.com/hands-on/playground/cloud-sandboxes'))
      .toEqual([
        'https://app.pluralsight.com/hands-on/playground/cloud-sandboxes',
        'https://app.pluralsight.com/cloud-playground/cloud-sandboxes',
      ]);
  });

  test('retries with the legacy route after the current route lands on s2 404', async () => {
    const page = makePage('https://s2.pluralsight.com/404.html', true);

    await navigateToSandbox(page, 'https://app.pluralsight.com/hands-on/playground/cloud-sandboxes');

    expect(page.goto).toHaveBeenNthCalledWith(
      1,
      'https://app.pluralsight.com/hands-on/playground/cloud-sandboxes',
      expect.any(Object)
    );
    expect(page.goto).toHaveBeenNthCalledWith(
      2,
      'https://app.pluralsight.com/cloud-playground/cloud-sandboxes',
      expect.any(Object)
    );
  });
});

describe('sandbox sign-in', () => {
  test('resolves when the page navigates to the current identity URL', async () => {
    const { page } = makeSignInPage();
    page.waitForURL
      .mockImplementationOnce(async (predicate) => expect(predicate(new URL('https://app.pluralsight.com/id'))).toBe(true))
      .mockImplementationOnce(async (predicate) => expect(predicate(new URL('https://app.pluralsight.com/hands-on/playground/cloud-sandboxes'))).toBe(true));

    await expect(handleSignIn(page)).resolves.toBeUndefined();
  });

  test('does not include the retired identity host in the sign-in link locator', async () => {
    const { page } = makeSignInPage();
    page.waitForURL.mockResolvedValue(undefined);

    await handleSignIn(page);

    expect(page.locator.mock.calls[0][0]).not.toContain('id.pluralsight.com');
  });

  test('post-login wait rejects the identity URL and accepts a sandbox URL', async () => {
    const { page } = makeSignInPage();
    page.waitForURL.mockResolvedValue(undefined);

    await handleSignIn(page);

    const postLoginPredicate = page.waitForURL.mock.calls[1][0];
    expect(postLoginPredicate(new URL('https://app.pluralsight.com/id'))).toBe(false);
    expect(postLoginPredicate(new URL('https://app.pluralsight.com/hands-on/playground/cloud-sandboxes'))).toBe(true);
  });
});
