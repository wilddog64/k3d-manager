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

## Releases

| Version | Date | Notes |
|---------|------|-------|
| [0.3.0](https://github.com/wilddog64/lib-acg/releases/tag/0.3.0) | 2026-05-21 | Make CFn template path configurable; fix credential extraction & extend flows; add pre-commit dangling-reference gate |
| [0.2.0](https://github.com/wilddog64/lib-acg/releases/tag/0.2.0) | 2026-05-20 | Fix ACG restart/extend Playwright scripts; add Playwright fixtures & CI e2e tests |
| [0.1.0](https://github.com/wilddog64/lib-acg/releases/tag/0.1.0) | 2026-05-19 | Initial release: Chrome CDP, ACG session mgmt, credential extraction |

See [docs/releases.md](docs/releases.md) for full release history.

## Issue Logs

Recent GitHub Issues and findings:

| Date | Issue | Notes |
|------|-------|-------|
| 2026-05-25 | [Copilot PR #29 Review](docs/issues/2026-05-25-copilot-pr29-review-findings.md) | `git grep -F` for fixed-string dangling-ref check; spec Rules wording clarified |
| 2026-05-21 | [Copilot PR #22 Review](docs/issues/2026-05-21-copilot-pr22-review-findings.md) | Template preflight check, README link, spec path corrections |
| 2026-05-21 | [Copilot PR #21 Review](docs/issues/2026-05-21-copilot-pr21-review-findings.md) | `AllowedCidr` default & hard-coded IAM role names in CloudFormation template |
| 2026-05-21 | [ACG Extend CDP Attach Failure](docs/issues/2026-05-21-acg-extend-cdp-attach-fails-on-chrome-147.md) | Chrome 147 requires `--enable-automation` to accept CDP attach; Playwright script updated |
| 2026-05-20 | [Copilot PR #18 Review](docs/issues/2026-05-20-copilot-pr18-review-findings.md) | ACG extend flow timing issues & SPA re-navigation challenges |
