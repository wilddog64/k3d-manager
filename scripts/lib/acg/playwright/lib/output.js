const fs = require('fs');
const os = require('os');
const path = require('path');

const CDP_HOST = process.env.PLAYWRIGHT_CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.PLAYWRIGHT_CDP_PORT || '9222';
const CDP_URL = `http://${CDP_HOST}:${CDP_PORT}`;
const AUTH_DIR_OVERRIDE = process.env.PLAYWRIGHT_AUTH_DIR;

const AUTH_DIR = AUTH_DIR_OVERRIDE ||
  path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'profile');

function _isFirstRun() {
  try {
    return !fs.existsSync(AUTH_DIR) || fs.readdirSync(AUTH_DIR).length === 0;
  } catch {
    return true;
  }
}

function _outputCredentials(data) {
  const credsFile = process.env.PLAYWRIGHT_CREDS_FILE;
  const output = Object.entries(data).map(([k, v]) => `${k}=${v}`).join('\n');

  if (credsFile) {
    fs.writeFileSync(credsFile, output, { mode: 0o600 });
    fs.chmodSync(credsFile, 0o600);
    console.error(`INFO: Credentials scrubbed to secure file: ${credsFile}`);
  } else {
    process.stdout.write(output + '\n');
  }
}

module.exports = {
  AUTH_DIR,
  CDP_URL,
  _isFirstRun,
  _outputCredentials,
};
