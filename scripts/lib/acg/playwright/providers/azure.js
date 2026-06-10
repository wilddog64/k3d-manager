async function extractCredentials(page, outputFn) {
  await page.waitForFunction(() => {
    const others = ['AWS', 'Google Cloud', 'GCP'];
    const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));
    return inputs.some(inp => {
      if (!inp.value.trim()) return false;
      let node = inp.parentElement;
      for (let j = 0; j < 12; j++) {
        if (!node) break;
        const t = node.innerText || '';
        if (/azure/i.test(t) && !others.some(p => t.includes(p))) return true;
        node = node.parentElement;
      }
      return false;
    });
  }, { timeout: 15000 });

  const { azureInputs, allInputs } = await page.evaluate(() => {
    function detectLabel(inp) {
      let node = inp.parentElement;
      for (let j = 0; j < 6; j++) {
        if (!node) break;
        const t = node.innerText || '';
        if (/client\s+secret|\bsecret\b/i.test(t)) return 'clientSecret';
        if (/client/i.test(t)) return 'clientId';
        if (/username|email/i.test(t)) return 'username';
        if (/\bpassword\b/i.test(t)) return 'password';
        if (/subscription/i.test(t)) return 'subscription';
        if (/tenant|directory/i.test(t)) return 'tenant';
        node = node.parentElement;
      }
      return null;
    }

    const others = ['AWS', 'Google Cloud', 'GCP'];
    const inputs = Array.from(document.querySelectorAll('input[aria-label="Copyable input"]'));

    const azureScoped = inputs.filter(inp => {
      let node = inp.parentElement;
      for (let j = 0; j < 12; j++) {
        if (!node) break;
        const t = node.innerText || '';
        if (/azure/i.test(t) && !others.some(p => t.includes(p))) return true;
        node = node.parentElement;
      }
      return false;
    }).map(inp => ({ fieldLabel: detectLabel(inp), fullValue: inp.value }));

    // Deep scan: walk 20 ancestors for subscription/tenant detection
    function detectLabelDeep(inp) {
      let node = inp.parentElement;
      for (let j = 0; j < 20; j++) {
        if (!node) break;
        const t = node.innerText || '';
        if (/subscription/i.test(t)) return 'subscription';
        if (/tenant|directory/i.test(t)) return 'tenant';
        node = node.parentElement;
      }
      return null;
    }

    const allScanned = inputs.map(inp => {
      const fl = detectLabel(inp) || detectLabelDeep(inp);
      return { fieldLabel: fl, fullValue: inp.value };
    });

    return { azureInputs: azureScoped, allInputs: allScanned };
  });

  console.error(`INFO: Found ${azureInputs.length} Azure-scoped copyable inputs.`);

  if (azureInputs.length === 0) {
    throw new Error('No credentials found in Azure provider card');
  }

  let username, password, subscriptionId, tenantId, clientId, clientSecret;

  // Pass 1: label-detected fields from Azure-scoped inputs
  for (const { fullValue: val, fieldLabel } of azureInputs) {
    if (fieldLabel === 'clientId' && !clientId) clientId = val;
    else if (fieldLabel === 'clientSecret' && !clientSecret) clientSecret = val;
    if (fieldLabel === 'username' && !username) username = val;
    else if (fieldLabel === 'password' && !password) password = val;
    else if (fieldLabel === 'subscription' && !subscriptionId) subscriptionId = val;
    else if (fieldLabel === 'tenant' && !tenantId) tenantId = val;
  }

  // Pass 2: if subscription or tenant still missing, scan all inputs by label
  if (!subscriptionId || !tenantId) {
    for (const { fullValue: val, fieldLabel } of allInputs) {
      if (fieldLabel === 'subscription' && !subscriptionId) subscriptionId = val;
      else if (fieldLabel === 'tenant' && !tenantId) tenantId = val;
    }
  }

  // Pass 3: UUID-pattern fallback — subscription and tenant are UUIDs, secret is not
  if (!subscriptionId || !tenantId) {
    const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    const uuidInputs = allInputs
      .filter(({ fullValue: v }) => uuidRe.test(v.trim()) && v.trim() !== clientId)
      .map(({ fullValue: v }) => v.trim());
    if (!subscriptionId && uuidInputs.length >= 1) subscriptionId = uuidInputs[0];
    if (!tenantId && uuidInputs.length >= 2) tenantId = uuidInputs[1];
  }

  // Pass 4: positional fallback for Azure-scoped inputs (4-field layout)
  if (!username && azureInputs.length >= 1) username = azureInputs[0].fullValue;
  if (!password && azureInputs.length >= 2) password = azureInputs[1].fullValue;
  if (!clientId && azureInputs.length >= 3) clientId = azureInputs[2].fullValue;
  if (!clientSecret && azureInputs.length >= 4) clientSecret = azureInputs[3].fullValue;

  const hasUserPass = username && password;
  const hasServicePrincipal = clientId && clientSecret;
  if (!hasUserPass && !hasServicePrincipal) {
    throw new Error('Could not find Azure credentials (expected username+password or clientId+secret)');
  }

  const creds = {};
  if (username) creds.AZURE_USERNAME = username.trim();
  if (password) creds.AZURE_PASSWORD = password.trim();
  if (clientId) creds.AZURE_CLIENT_ID = clientId.trim();
  if (clientSecret) creds.AZURE_CLIENT_SECRET = clientSecret.trim();
  if (subscriptionId) creds.AZURE_SUBSCRIPTION_ID = subscriptionId.trim();
  if (tenantId) creds.AZURE_TENANT_ID = tenantId.trim();
  outputFn(creds);
}

module.exports = { extractCredentials };
