const {
  _isSandboxPageUrl,
  _normalizeSandboxUrl,
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
