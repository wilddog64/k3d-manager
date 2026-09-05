const {
  navigateToSandbox,
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
