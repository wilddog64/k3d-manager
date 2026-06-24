const { _findScopedButton, _capturePageDebugState } = require('../lib/sandbox');

function _normalize(text) {
  return (text || '').replace(/\s+/g, ' ').trim();
}

function _extractResourceGroup(bodyText, currentUrl) {
  const urlMatch = String(currentUrl || '').match(/\/resourceGroups\/([^/?#]+)/i);
  if (urlMatch) return decodeURIComponent(urlMatch[1]);

  const lines = String(bodyText || '')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean);

  const rgLabelIdx = lines.findIndex(line => /^resource group$/i.test(line));
  if (rgLabelIdx > 0) return lines[rgLabelIdx - 1];

  const rgInlineMatch = String(bodyText || '').match(/resource group\s*[:\-]\s*([^\n]+)/i);
  if (rgInlineMatch) return rgInlineMatch[1].trim();

  return '';
}

function _extractSubscriptionId(bodyText, currentUrl) {
  const urlMatch = String(currentUrl || '').match(/\/subscriptions\/([0-9a-f-]{36})/i);
  if (urlMatch) return urlMatch[1];

  const lines = String(bodyText || '')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean);

  const subLabelIdx = lines.findIndex(line => /^subscription id$/i.test(line));
  if (subLabelIdx >= 0 && lines[subLabelIdx + 1]) return lines[subLabelIdx + 1];

  const subInlineMatch = String(bodyText || '').match(/subscription id\s*[:\-]\s*([0-9a-f-]{36})/i);
  if (subInlineMatch) return subInlineMatch[1];

  return '';
}

function _extractTenantFromVisibleText(bodyText) {
  const text = String(bodyText || '');
  const tenantMatches = [
    text.match(/tenant id\s*[:\-]\s*([0-9a-f-]{36})/i),
    text.match(/directory id\s*[:\-]\s*([0-9a-f-]{36})/i),
  ].filter(Boolean);
  return tenantMatches.length > 0 ? tenantMatches[0][1] : '';
}

async function _discoverTenantId(page, username, bodyText) {
  const visibleTenant = _extractTenantFromVisibleText(bodyText);
  if (visibleTenant) return visibleTenant;

  if (!username) return '';
  const domain = username.includes('@') ? username.split('@').slice(1).join('@') : '';
  if (!domain) return '';

  const oidcUrl = `https://login.microsoftonline.com/${domain}/.well-known/openid-configuration`;
  console.error(`INFO: AZURE_TENANT_ID not in UI — discovering via OIDC endpoint for ${domain}...`);
  let discovered = '';
  try {
    const res = await fetch(oidcUrl, { cache: 'no-store' });
    if (res.ok) {
      const data = await res.json();
      const tokenEndpoint = data && data.token_endpoint ? String(data.token_endpoint) : '';
      const parts = tokenEndpoint.split('/');
      discovered = parts.length > 3 ? parts[3] : '';
    }
  } catch {
    discovered = '';
  }

  if (discovered) {
    console.error('INFO: Discovered tenant: ***');
  } else {
    console.error(`WARN: OIDC discovery failed for domain ${domain}`);
  }
  return discovered;
}

async function _scanAzurePage(page) {
  return page.evaluate(() => {
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

    return {
      azureInputs: azureScoped,
      allInputs: allScanned,
      bodyText: document.body ? (document.body.innerText || '') : '',
      currentUrl: location.href,
    };
  });
}

async function extractCredentials(page, outputFn) {
  try {
    let scan = await _scanAzurePage(page);
    let reopened = false;

    if (scan.azureInputs.length === 0) {
      const openBtn = await _findScopedButton(page, 'Open Sandbox', 'Azure', 1500);
      if (openBtn && !reopened) {
        console.error('INFO: Azure panel closed — re-opening to retrieve credentials...');
        await openBtn.click({ force: true }).catch(() => {});
        await page.waitForTimeout(3000);
        reopened = true;
        scan = await _scanAzurePage(page);
      }
    }

    console.error(`INFO: Found ${scan.azureInputs.length} Azure-scoped copyable inputs.`);

    if (scan.azureInputs.length === 0) {
      throw new Error('No credentials found in Azure provider card');
    }

    let username, password, subscriptionId, tenantId, clientId, clientSecret;

    for (const { fullValue: val, fieldLabel } of scan.azureInputs) {
      if (fieldLabel === 'clientId' && !clientId) clientId = val;
      else if (fieldLabel === 'clientSecret' && !clientSecret) clientSecret = val;
      else if (fieldLabel === 'username' && !username) username = val;
      else if (fieldLabel === 'password' && !password) password = val;
      else if (fieldLabel === 'subscription' && !subscriptionId) subscriptionId = val;
      else if (fieldLabel === 'tenant' && !tenantId) tenantId = val;
    }

    if (!subscriptionId || !tenantId) {
      for (const { fullValue: val, fieldLabel } of scan.allInputs) {
        if (fieldLabel === 'subscription' && !subscriptionId) subscriptionId = val;
        else if (fieldLabel === 'tenant' && !tenantId) tenantId = val;
      }
    }

    if (!subscriptionId || !tenantId) {
      const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      const uuidInputs = scan.allInputs
        .filter(({ fullValue: v }) => uuidRe.test(String(v || '').trim()) && String(v || '').trim() !== clientId)
        .map(({ fullValue: v }) => String(v || '').trim());
      if (!subscriptionId && uuidInputs.length >= 1) subscriptionId = uuidInputs[0];
      if (!tenantId && uuidInputs.length >= 2) tenantId = uuidInputs[1];
    }

    if (!username && scan.azureInputs.length >= 1) username = scan.azureInputs[0].fullValue;
    if (!password && scan.azureInputs.length >= 2) password = scan.azureInputs[1].fullValue;
    if (!clientId && scan.azureInputs.length >= 3) clientId = scan.azureInputs[2].fullValue;
    if (!clientSecret && scan.azureInputs.length >= 4) clientSecret = scan.azureInputs[3].fullValue;

    const hasUserPass = username && password;
    const hasServicePrincipal = clientId && clientSecret;
    if (!hasUserPass && !hasServicePrincipal) {
      throw new Error('Could not find Azure credentials (expected username+password or clientId+secret)');
    }

    const bodyText = scan.bodyText || '';
    const currentUrl = scan.currentUrl || page.url();
    const resourceGroup = _extractResourceGroup(bodyText, currentUrl);
    const portalTenant = tenantId || await _discoverTenantId(page, username || '', bodyText);
    const snapshot = await _capturePageDebugState(page, 'azure', 'Azure credential snapshot captured after extraction').catch(() => null);

    const creds = {};
    if (username) creds.AZURE_USERNAME = _normalize(username);
    if (password) creds.AZURE_PASSWORD = _normalize(password);
    if (clientId) creds.AZURE_CLIENT_ID = _normalize(clientId);
    if (clientSecret) creds.AZURE_CLIENT_SECRET = _normalize(clientSecret);
    if (subscriptionId) creds.AZURE_SUBSCRIPTION_ID = _normalize(subscriptionId);
    if (portalTenant) creds.AZURE_TENANT_ID = _normalize(portalTenant);
    if (resourceGroup) creds.AZURE_RESOURCE_GROUP = _normalize(resourceGroup);
    if (snapshot && snapshot.screenshotPath) creds.AZURE_SCREENSHOT_PATH = snapshot.screenshotPath;
    if (currentUrl) creds.AZURE_PORTAL_URL = currentUrl;

    outputFn(creds);
  } catch (error) {
    await _capturePageDebugState(page, 'azure', error.message).catch(() => {});
    throw error;
  }
}

module.exports = { extractCredentials };
