// NOTE: GCP credential extraction is fragile — positional index fallback, minimal test
// coverage. Functional parity preserved from original; do not refactor further here.
const fs = require('fs');
const os = require('os');
const path = require('path');

async function extractCredentials(page, outputFn) {
  await page.waitForSelector('text=Username', { timeout: 15000 });

  const allInputs = await page.locator('input, textarea').all();
  console.error(`INFO: Found ${allInputs.length} input/textarea elements on page`);
  for (let i = 0; i < allInputs.length; i++) {
    const tag = await allInputs[i].evaluate(el => el.tagName.toLowerCase());
    const ariaLabel = await allInputs[i].getAttribute('aria-label');
    const val = await allInputs[i].inputValue().catch(() => '');
    const visible = await allInputs[i].isVisible();
    console.error(`INFO: [${i}] <${tag}> aria-label="${ariaLabel}" visible=${visible} value="${val.length > 0 ? '[set]' : '[empty]'}"`);
  }

  const inputs = await page.locator('input[aria-label="Copyable input"]').all();
  console.error(`INFO: Found ${inputs.length} copyable inputs`);

  const username = inputs.length >= 1 ? await inputs[0].inputValue().catch(() => '') : '';
  const password = inputs.length >= 2 ? await inputs[1].inputValue().catch(() => '') : '';
  const serviceAccountJson = inputs.length >= 3 ? await inputs[2].inputValue().catch(() => '') : '';

  console.error(`INFO: username="${username.slice(0, 30)}" password="${password ? '[set]' : '[empty]'}" sa_json_len=${serviceAccountJson.length}`);

  if (!serviceAccountJson) {
    throw new Error('Could not find Service Account Credentials field');
  }

  let projectId;
  try {
    projectId = JSON.parse(serviceAccountJson).project_id;
  } catch {
    throw new Error('Service Account Credentials is not valid JSON');
  }
  if (!projectId) {
    throw new Error('project_id not found in Service Account Credentials JSON');
  }

  const keyDir = path.join(os.homedir(), '.local', 'share', 'k3d-manager');
  const keyPath = path.join(keyDir, 'gcp-service-account.json');
  fs.mkdirSync(keyDir, { recursive: true });
  fs.writeFileSync(keyPath, serviceAccountJson, { mode: 0o600 });
  fs.chmodSync(keyPath, 0o600);
  console.error(`INFO: Service account key written to ${keyPath}`);

  outputFn({
    GCP_PROJECT: projectId,
    GCP_USERNAME: username.trim(),
    GCP_PASSWORD: password.trim(),
    GOOGLE_APPLICATION_CREDENTIALS: keyPath
  });
}

module.exports = { extractCredentials };
