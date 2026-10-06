const {
  _findExtendButton,
  _isSandboxPageUrl,
  _normalizeSandboxUrl,
  _remainingMinsFromShutdown,
  _safeButtonLabels,
  _selectExtendPage,
} = require('../../playwright/acg_extend');

function makePage(url) {
  return { url: jest.fn(() => url) };
}

describe('acg_extend sandbox-page routing', () => {
  test('normalizes legacy cloud-playground sandbox URLs to hands-on path', () => {
    expect(
      _normalizeSandboxUrl('https://app.pluralsight.com/cloud-playground/cloud-sandboxes')
    ).toBe('https://app.pluralsight.com/hands-on/playground/cloud-sandboxes');
  });

  test('treats s2 404 tab as not being on the sandbox page', () => {
    expect(_isSandboxPageUrl('https://s2.pluralsight.com/404.html')).toBe(false);
    expect(_isSandboxPageUrl('https://app.pluralsight.com/hands-on/playground/cloud-sandboxes')).toBe(true);
  });

  test('does not treat generic playground pages as sandbox pages', () => {
    expect(_isSandboxPageUrl('https://app.pluralsight.com/cloud-playground')).toBe(false);
    expect(_isSandboxPageUrl('https://app.pluralsight.com/hands-on/playground')).toBe(false);
    expect(
      _isSandboxPageUrl('https://app.pluralsight.com/hands-on/playground/cloud-sandboxes/abc123')
    ).toBe(true);
  });

  test('prefers an actual sandbox tab over a generic pluralsight tab', () => {
    const page404 = makePage('https://s2.pluralsight.com/404.html');
    const sandboxPage = makePage('https://app.pluralsight.com/hands-on/playground/cloud-sandboxes');

    expect(_selectExtendPage([page404, sandboxPage])).toBe(sandboxPage);
  });
});

describe('acg_extend button wait', () => {
  let errorSpy;

  beforeEach(() => {
    errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    errorSpy.mockRestore();
  });

  function makeButtonPage(isVisible) {
    const state = { reloaded: false };
    const page = {
      locator: jest.fn((selector) => ({
        first: () => ({
          isVisible: async () => isVisible(selector, state),
          click: jest.fn(async () => {}),
        }),
      })),
      waitForTimeout: async () => {},
      waitForFunction: async () => {},
      goto: jest.fn(async () => {
        state.reloaded = true;
      }),
    };
    return { page, state };
  }

  test('finds a button that renders after the first poll without reloading', async () => {
    let calls = 0;
    const { page } = makeButtonPage((selector) => {
      calls += 1;
      return selector === 'button:has-text("Extend")' && calls >= 3;
    });

    const result = await _findExtendButton(page, ['button:has-text("Extend")'], 'https://example.test', 50);

    expect(result).not.toBeNull();
    expect(page.goto).not.toHaveBeenCalled();
  });

  test('reloads once when the button never appears on the first page', async () => {
    const { page } = makeButtonPage((selector, state) => (
      selector === 'button:has-text("Extend")' && state.reloaded
    ));

    const result = await _findExtendButton(page, ['button:has-text("Extend")'], 'https://example.test/sandbox', 50);

    expect(result).not.toBeNull();
    expect(page.goto).toHaveBeenCalledTimes(1);
    expect(page.goto).toHaveBeenCalledWith('https://example.test/sandbox', {
      waitUntil: 'domcontentloaded',
      timeout: 30000,
    });
  });

  test('returns null when the button never appears', async () => {
    const { page } = makeButtonPage(() => false);

    const result = await _findExtendButton(page, ['button:has-text("Extend")'], 'https://example.test/sandbox', 50);

    expect(result).toBeNull();
    expect(page.goto).toHaveBeenCalledTimes(1);
  });

  test('drops credential-shaped button labels', () => {
    expect(_safeButtonLabels([
      'Open Sandbox',
      '  Extend\n Sandbox ',
      'AKIAABCDEFGHIJKLMNOP',
      'x'.repeat(80),
      'Open Sandbox',
      '',
    ])).toEqual(['Open Sandbox', 'Extend Sandbox']);
  });
});

describe('acg_extend remaining TTL from the shutdown time of day', () => {
  const at = (h, m) => new Date(2026, 9, 6, h, m, 0, 0);

  test('reads a shutdown later today as the time left', () => {
    expect(_remainingMinsFromShutdown(23, 24, at(21, 42))).toBe(102);
  });

  test('reads a shutdown just past midnight as tomorrow', () => {
    expect(_remainingMinsFromShutdown(0, 30, at(23, 59))).toBe(31);
  });

  test('reads a shutdown earlier today as expired', () => {
    expect(_remainingMinsFromShutdown(14, 2, at(16, 0))).toBe(-118);
  });

  test('reads yesterday evening shutdown seen after midnight as expired, not ~22h left', () => {
    expect(_remainingMinsFromShutdown(23, 24, at(1, 12))).toBe(-108);
  });

  test('keeps a shutdown up to 6 hours ahead as the time left', () => {
    expect(_remainingMinsFromShutdown(4, 0, at(22, 30))).toBe(330);
    expect(_remainingMinsFromShutdown(19, 0, at(13, 0))).toBe(360);
  });
});
