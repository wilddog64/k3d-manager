async function extractCredentials(page, outputFn) {
  await page.waitForSelector('input[aria-label="Copyable input"]', { timeout: 15000 });
  const inputs = await page.locator('input[aria-label="Copyable input"]').all();
  console.error(`INFO: Found ${inputs.length} copyable inputs.`);

  let accessKey, secretKey, sessionToken;
  for (let i = 0; i < inputs.length; i++) {
    const val = await inputs[i].inputValue();
    const parent = await inputs[i].evaluateHandle(el => el.closest('div')?.parentElement ?? null);
    const text = parent ? await parent.evaluate(el => el.innerText || '') : '';

    if (text.toLowerCase().includes('access key id')) {
      accessKey = val;
    } else if (text.toLowerCase().includes('secret access key')) {
      secretKey = val;
    } else if (text.toLowerCase().includes('session token')) {
      sessionToken = val;
    }
  }

  if (!accessKey && inputs.length >= 3) {
    accessKey = await inputs[2].inputValue();
  }
  if (!secretKey && inputs.length >= 4) {
    secretKey = await inputs[3].inputValue();
  }
  if (!sessionToken && inputs.length >= 5) {
    sessionToken = await inputs[4].inputValue();
  }

  if (accessKey && secretKey) {
    const creds = {
      AWS_ACCESS_KEY_ID: accessKey.trim(),
      AWS_SECRET_ACCESS_KEY: secretKey.trim()
    };
    if (sessionToken) creds.AWS_SESSION_TOKEN = sessionToken.trim();
    outputFn(creds);
  } else {
    throw new Error('Could not find AWS Access Key and Secret Key');
  }
}

module.exports = { extractCredentials };
