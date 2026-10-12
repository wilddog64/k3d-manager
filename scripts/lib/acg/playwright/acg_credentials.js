const { connectBrowser } = require('./lib/browser');
const { findOrCreatePage, navigateToSandbox, waitForSkeleton, handleSignIn, startSandbox } = require('./lib/sandbox');
const { _outputCredentials, _isFirstRun, AUTH_DIR } = require('./lib/output');
const providers = {
  aws: require('./providers/aws'),
  gcp: require('./providers/gcp'),
  azure: require('./providers/azure'),
};

async function extractCredentials() {
  let targetUrl = process.argv[2];
  if (!targetUrl) {
    console.error('ERROR: No target URL provided');
    process.exit(1);
  }
  const providerIdx = process.argv.indexOf('--provider');
  const provider = (providerIdx !== -1 && process.argv[providerIdx + 1])
    ? process.argv[providerIdx + 1]
    : 'aws';

  if (!providers[provider]) {
    console.error(`ERROR: Unknown provider '${provider}' (expected 'aws', 'gcp', or 'azure')`);
    process.exit(1);
  }
  console.error(`INFO: Using provider ${provider}`);

  if (_isFirstRun()) {
    console.error('BOOTSTRAP: Auth dir is empty — first run detected.');
    console.error(`BOOTSTRAP: Auth dir: ${AUTH_DIR}`);
    console.error('BOOTSTRAP: Chrome will open. Please log in to Pluralsight when prompted.');
    console.error('BOOTSTRAP: The script will continue automatically after successful login (up to 300s).');
  }

  const { browserContext, cdpBrowser } = await connectBrowser();
  let page = null;
  try {
    const context = browserContext;
    if (!context) throw new Error('No browser context found');

    page = await findOrCreatePage(context);
    await navigateToSandbox(page, targetUrl);
    await waitForSkeleton(page);
    await handleSignIn(page, targetUrl);
    await startSandbox(page, targetUrl, provider);

    console.error('INFO: Extracting credentials...');
    await providers[provider].extractCredentials(page, _outputCredentials);
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    throw error;
  } finally {
    if (page && page.__libAcgWasCreated) {
      try { await page.close(); } catch {}
    }
    if (cdpBrowser) {
      try { await cdpBrowser.disconnect(); } catch {}
      console.error('INFO: Detached from Chrome CDP session.');
    } else if (browserContext) {
      await browserContext.close();
    }
  }
}

const OVERALL_TIMEOUT_MS = 780000;
let _timeoutHandle;
const _timeoutPromise = new Promise((_, reject) => {
  _timeoutHandle = setTimeout(
    () => reject(new Error(`Script timed out after ${OVERALL_TIMEOUT_MS / 1000}s`)),
    OVERALL_TIMEOUT_MS
  );
});

Promise.race([extractCredentials(), _timeoutPromise])
  .then(() => {
    clearTimeout(_timeoutHandle);
    process.exit(0);
  })
  .catch(err => {
    clearTimeout(_timeoutHandle);
    console.error(`ERROR: ${err.message}`);
    process.exit(1);
  });
