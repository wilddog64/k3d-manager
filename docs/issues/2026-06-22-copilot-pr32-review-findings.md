# Copilot review findings — PR #32 (v0.4.0 acg absorption)

**PR:** https://github.com/wilddog64/lib-foundation/pull/32
**Review:** `copilot-pull-request-reviewer[bot]`, 2026-06-23, state COMMENTED — 12 inline findings.
**Context:** PR #32 absorbs lib-acg into `scripts/lib/acg/` as a **verbatim clean tree-copy** from
lib-acg `7708ea31` (v0.1.9). The byte-for-byte fidelity of that copy was load-bearing — a prior
deviation (hoisting `bin/` to the repo root) regressed the live Playwright sandbox-delete flow.
Findings are therefore triaged by whether they touch **this PR's own new files** or **pre-existing
imported lib-acg code**.

---

## Fixed in this PR

| # | File:line | Finding | Fix |
|---|-----------|---------|-----|
| 5 | `Makefile:11` | `setup` help text says `npm install` | help text → `npm ci` (`f3f2fbd`) |
| 6 | `Makefile:25` | `setup` recipe `npm install` can drift from lockfile vs CI's `npm ci` | recipe → `npm ci` (`f3f2fbd`) |

The `Makefile` is a lib-foundation-authored delegating wrapper (not imported verbatim), so the
`npm ci` consistency fix is in scope and risk-free (dev-only target, not on the live credential path).

---

## Fixed in PR #32 — hardening commit `cbe203f`

These were pre-existing in the verbatim lib-acg import (`7708ea31`). The user elected to fold the
full hardening into PR #32 rather than defer. Spec: `docs/bugs/2026-06-22-acg-cdp-env-and-creds-injection-hardening.md`.
All 8 changes applied; `npm run check` + `npm test` (10/10) + `shellcheck -S warning` green; defaults
unchanged (`127.0.0.1:9222`). **Live re-run (2026-06-22):** `make credential-test PROVIDER=aws`
PASSED both scenarios (sandbox-exists reuse + sandbox-delete/restart), ending in
`sts:GetCallerIdentity OK` — the threaded CDP host/port did not regress the live AWS flow. The
GCP-extract and `PLAYWRIGHT_CDP_PORT`-override paths remain unexercised live (low risk; defaults
unchanged). Separately, the live run surfaced a pre-existing (non-PR-#32) bug: `acg-credential-test:277`
calls an undefined `_sts_valid`, forcing a spurious sandbox restart on every happy-path run — tracked
as a follow-up in `memory-bank/progress.md`.

| # | File:line | Finding | Severity |
|---|-----------|---------|----------|
| 1 | `playwright/lib/output.js:27` | `writeFileSync(..., {mode:0o600})` does not reliably tighten perms on an existing creds file across platforms | med (secret hygiene) |
| 2 | `gcp.sh:104` | `source`s a creds file built from browser-extracted values — unescaped `$()`/backticks/newlines = shell injection (OWASP A03) | **high** |
| 3 | `vars.sh:6` | header comment references old lib-acg paths (`scripts/etc/...`, `scripts/plugins/...`) | low (stale comment) |
| 4 | `vars.sh:20` | comment points at `scripts/plugins/acg.sh`; constant now lives in `scripts/lib/acg/acg.sh` | low (stale comment) |
| 7 | `acg.sh:302` | CDP probe hard-codes `localhost:9222`, ignoring `_ACG_CHROME_CDP_PORT`/`PLAYWRIGHT_CDP_PORT` | med (config) |
| 8 | `cdp.sh:88` | `_browser_launch` hard-codes 9222 in probe, log, and Chrome launch args | med (config) |
| 9 | `cdp.sh:94` | `open -a "Google Chrome"` fallback hard-codes 9222 | med (config) |
| 10 | `playwright/acg_extend.js:99` | CDP URL hard-coded `localhost:9222`, ignores `PLAYWRIGHT_CDP_HOST/PORT` | med (config) |
| 11 | `playwright/acg_restart.js:9` | hard-codes CDP host/port instead of honoring env | med (config) |
| 12 | `acg_session_check.js:6` | CDP URL hard-coded `127.0.0.1:9222`, ignores `PLAYWRIGHT_CDP_HOST/PORT` | med (config) |

### How each was fixed (commit `cbe203f`)

- **CDP port/host consistency (#7–#12):** `PLAYWRIGHT_CDP_HOST`/`PLAYWRIGHT_CDP_PORT` threaded through
  every CDP entry point (`cdp.sh` `_browser_launch`, `acg.sh` probe, `acg_extend.js`, `acg_restart.js`,
  `acg_session_check.js`). Defaults unchanged.
- **gcp.sh creds injection (#2):** `source "${creds_tmp}"` replaced with an allowlisted key=value
  parser (`GCP_PROJECT`/`GOOGLE_APPLICATION_CREDENTIALS`/`GCP_USERNAME`/`GCP_PASSWORD`) — values
  assigned literally, never evaluated.
- **output.js perms (#1):** `fs.chmodSync(credsFile, 0o600)` added after the write so the mode is
  enforced on pre-existing creds files.
- **vars.sh stale comments (#3, #4):** updated to the `scripts/lib/acg/...` module paths.

All 12 Copilot threads replied to with the fix SHA and resolved.

---

## Process note

The verbatim-import principle and the "address Copilot findings" gate are in tension for an
absorption PR. Resolution adopted here: fix findings on **PR-authored files** immediately; for
**verbatim-imported** files, write a spec first (`docs/bugs/`) and — when the user opts in, as they
did for PR #32 — apply it in-PR with the defaults held constant, so the import stays behavior-faithful
and the live flow is not re-regressed.
