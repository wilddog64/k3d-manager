# CLAUDE.md — lib-acg

Browser automation library for ACG sandbox credential extraction and session management.
Provides Chrome CDP bootstrap, Playwright scripts, and provider-specific credential flows
(AWS, GCP). Consumed by `k3d-manager` via git subtree.

**Entry point:** `scripts/plugins/acg.sh`, `scripts/plugins/gcp.sh`
**Current state:** `memory-bank/activeContext.md` and `memory-bank/progress.md`
**Task specs:** `docs/plans/`

## Claude Session Rules

- **Memory-bank update is mandatory and immediate** — after every completed action, update
  `memory-bank/activeContext.md` and `memory-bank/progress.md` before doing anything else.
- **PR creation gate** — do NOT create a PR until CI green and Copilot review addressed.
- **Verify before trust** — never trust a commit SHA or BATS result from any agent without
  independently verifying via `git log`.

---

## Layout

```
scripts/
  lib/
    foundation/      # git subtree from lib-foundation (system.sh, agent_rigor.sh)
    cdp.sh           # Chrome CDP primitives: _browser_launch, _cdp_ensure_acg_session
  plugins/
    acg.sh           # ACG sandbox lifecycle: acg_get_credentials, acg_extend, acg_provision
    gcp.sh           # GCP identity bridge: gcp_login
  vars.sh            # Shared constants: PLAYWRIGHT_AUTH_DIR, PLAYWRIGHT_CDP_PORT, URLs
playwright/
  acg_credentials.js # AWS/GCP credential extraction via Playwright
  acg_extend.js      # Sandbox TTL extension via Playwright
  gcp_login.js       # GCP OAuth automation via Playwright
memory-bank/         # activeContext.md + progress.md — read first, update after
docs/plans/          # Task specs for Codex/Gemini assignments
```

## Code Style

- `set -euo pipefail` on all new bash scripts
- LF line endings only
- `shellcheck -S warning` must pass on all `.sh` files
- `node --check` must pass on all `.js` files
- No inline comments unless the WHY is non-obvious

## Security Rules

- Never hardcode credentials — use `${PLACEHOLDER}` or env vars
- Double-quote all variable expansions: `"$var"` not `$var`
- Never pass external input to `eval`
