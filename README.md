# lib-acg

Browser automation library for ACG (A Cloud Guru / Pluralsight) sandbox credential
extraction and session management.

Provides:
- **Chrome CDP bootstrap** — ensures Chrome is running with remote debugging on port 9222
- **ACG session management** — Pluralsight login check and session recovery
- **Playwright scripts** — AWS credential extraction, GCP OAuth, sandbox TTL extension
- **Provider plugins** — `acg.sh` (sandbox lifecycle), `gcp.sh` (GCP identity bridge)

## Consumed by

- [`k3d-manager`](https://github.com/wilddog64/k3d-manager) — via git subtree at `scripts/lib/acg/`

## Structure

```
scripts/lib/cdp.sh         Chrome CDP primitives
scripts/plugins/acg.sh     ACG sandbox lifecycle
scripts/plugins/gcp.sh     GCP identity bridge
scripts/vars.sh            Shared Playwright constants
playwright/                Node.js Playwright scripts
```

## Development

```bash
# Install Playwright
npm install

# Lint
shellcheck -S warning scripts/**/*.sh
node --check playwright/*.js
```
