const { chromium } = require('playwright');
const http = require('http');
const { AUTH_DIR, CDP_URL } = require('./output');

const CDP_ENDPOINT = new URL(CDP_URL);

async function connectBrowser() {
  let browserContext;
  let cdpBrowser = null;

  try {
    try {
      cdpBrowser = await chromium.connectOverCDP(CDP_URL);
      const cdpContexts = cdpBrowser.contexts();
      if (cdpContexts.length > 0) {
        const cdpContext = cdpContexts[0];
        const cdpPages = cdpContext.pages();
        const cdpPsPage = cdpPages.find(p => {
          try {
            return new URL(p.url()).hostname.endsWith('.pluralsight.com');
          } catch {
            return false;
          }
        });
        if (cdpPsPage) {
          console.error('INFO: Found existing Pluralsight session via CDP — reusing existing Chrome instance.');
        } else {
          console.error('INFO: CDP browser has no Pluralsight tab — opening sandbox tab in existing Chrome context.');
        }
        browserContext = cdpContext;
      }
      if (!browserContext) {
        console.error('INFO: CDP connected but no open contexts — opening blank tab to expose profile context.');
        try {
          await new Promise((resolve, reject) => {
            const req = http.request(
              { hostname: CDP_ENDPOINT.hostname, port: CDP_ENDPOINT.port, path: '/json/new', method: 'PUT' },
              res => { res.resume(); resolve(); }
            );
            req.on('error', reject);
            req.end();
          });
          await new Promise(r => setTimeout(r, 500));
          try { await cdpBrowser.disconnect(); } catch {}
          cdpBrowser = await chromium.connectOverCDP(CDP_URL);
          const refreshedContexts = cdpBrowser.contexts();
          if (refreshedContexts.length > 0) {
            browserContext = refreshedContexts[0];
            console.error('INFO: Default Chrome context now accessible after blank tab + reconnect.');
          }
        } catch {
          /* fall through if blank tab fails */
        }
        if (!browserContext) {
          try { await cdpBrowser.disconnect(); } catch {}
          cdpBrowser = null;
        }
      }
    } catch {
      cdpBrowser = null;
    }

    if (!browserContext) {
      browserContext = await chromium.launchPersistentContext(AUTH_DIR, {
        headless: false,
        channel: 'chrome',
        args: ['--password-store=basic'],
      });
    }

    return { browserContext, cdpBrowser };
  } catch (error) {
    if (cdpBrowser) {
      try { await cdpBrowser.disconnect(); } catch {}
    }
    throw error;
  }
}

module.exports = { connectBrowser };
