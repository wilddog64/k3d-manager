# Active Context — lib-acg

## Current Branch: `fix/acg-credentials-cdp-context-reuse`

**Repo created:** 2026-04-25
**Status:** Phase 3 migration and Phase 5 CI content are on `main` (`5c0e8e2`). Current work fixes ACG credential extraction so k3d-manager `make up` can automate Step 1 without manual credential paste after first sign-in.

## Phase Status

- [x] **Phase 2** — COMPLETE. Repo skeleton created; lib-foundation subtree pending.
- [x] **Phase 3** — COMPLETE. Migrated acg.sh, gcp.sh, playwright scripts, vars.sh, and
      extracted _browser_launch + _cdp_ensure_acg_session into scripts/lib/cdp.sh.
      Source commit on main: `5c0e8e2`.
- [x] **ACG credential extraction misses visible sandbox** — FIXED in PR #2 (`https://github.com/wilddog64/lib-acg/pull/2`). Copilot review comments addressed and both inline threads resolved. Latest code commit `1ddbf7c` has GitHub Actions CI green; local checks passed (`npm run check`, `node --check playwright/acg_credentials.js`, `shellcheck scripts/**/*.sh`). Merge is blocked only because the PR is still draft: connector ready-for-review mutation failed with a response-shape error, shell GitHub token returned 401, and GitHub rejected merge with `Pull Request is still a draft`. Bug: `docs/bugs/2026-04-28-acg-credentials-cdp-context-miss.md`.

## Consumed By

- `k3d-manager` — will pull via git subtree at `scripts/lib/acg/` (Phase 4)
