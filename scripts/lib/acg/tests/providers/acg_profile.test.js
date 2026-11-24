const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const scripts = path.resolve(__dirname, '../../playwright');
let home, preload;
beforeEach(() => {
  home = fs.mkdtempSync(path.join(os.tmpdir(), 'acg-profile-test-'));
  expect(home).not.toBe(os.homedir());
  preload = path.join(home, 'mock.js');
  fs.writeFileSync(preload, `
    const timer = global.setTimeout;
    global.setTimeout = (fn, ms, ...args) => { const handle = timer(fn, ms, ...args); if (ms === 240000) handle.unref(); return handle; };
    const Module = require('module');
    const original = Module._load;
    Module._load = function(name, ...args) {
      if (name !== 'playwright') return original.call(this, name, ...args);
      return { chromium: {
        connectOverCDP: async () => {
          if (process.env.CDP_DOWN) throw Error('offline');
          return { contexts: () => [{ pages: () => [{
            url: () => 'https://app.pluralsight.com/cloud-sandboxes',
            locator: () => ({ first: () => ({ isVisible: async () => true }) })
          }] }], close: async () => {} };
        },
        launchPersistentContext: async dir => { throw Error('LAUNCH_DIR=' + dir); }
      } };
    };
  `);
});
afterEach(() => fs.rmSync(home, { recursive: true, force: true }));
function run(script, env = {}) {
  return spawnSync(process.execPath, ['--require', preload, path.join(scripts, script), 'https://example.test/cloud-sandboxes'], {
    env: { ...process.env, HOME: home, PLAYWRIGHT_AUTH_DIR: '', ...env }, encoding: 'utf8', timeout: 5000,
  });
}
test('extend uses CDP without a profile directory', () => {
  const result = run('acg_extend.js');
  expect(result.status).toBe(0);
  expect(result.stderr).toContain('Connected via CDP');
  expect(fs.existsSync(path.join(home, '.local/share/k3d-manager/profile'))).toBe(false);
});
test('extend requires a bootstrapped profile when CDP is down', () => {
  const result = run('acg_extend.js', { CDP_DOWN: '1' });
  expect(result.status).toBe(1);
  expect(result.stderr).toContain('acg_get_credentials');
  expect(result.stderr).toContain(path.join(home, '.local/share/k3d-manager/pw-profile'));
});
test.each(['acg_extend.js', 'acg_restart.js'])('%s uses configured and default profile on fallback', script => {
  const custom = path.join(home, 'custom');
  for (const [setting, expected] of [['', path.join(home, '.local/share/k3d-manager/pw-profile')], [custom, custom]]) {
    fs.mkdirSync(expected, { recursive: true });
    fs.writeFileSync(path.join(expected, 'session'), 'session');
    const result = run(script, { CDP_DOWN: '1', PLAYWRIGHT_AUTH_DIR: setting, PLAYWRIGHT_CDP_PORT: '1' });
    expect(result.status).toBe(1);
    expect(result.stderr).toContain(`LAUNCH_DIR=${expected}`);
  }
});
