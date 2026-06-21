# Copilot Review Findings — agy migration upstream PRs (2026-06-21)

Two upstream PRs land the gemini-cli → Antigravity (`agy`) migration in the repos that own
the code (subtree sources for k3d-manager):

- **lib-acg PR [#45](https://github.com/wilddog64/lib-acg/pull/45)** — `feat/v0.1.8`, fix commit `dd564c2`
- **lib-foundation PR [#31](https://github.com/wilddog64/lib-foundation/pull/31)** — `feat/ensure-agy-cli`, fix commit `9bdf776`

Both PRs: CI green on the fix commit, all Copilot threads resolved.

---

## lib-acg #45 — `scripts/lib/acg_session_check.js`, `scripts/lib/cdp.sh`

### Finding 1 — false-positive `ACG_SESSION_OK` on failed signin navigation (acg_session_check.js)

Copilot: if `page.goto(SIGNIN_URL)` fails, the `.catch(() => {})` swallows it; `page.url()`
then does not contain `/signin`, so the poll loop immediately treats the session as OK. Also,
throwing when `context.pages()` is empty breaks CDP sessions with no open tabs.

**Fix (`dd564c2`):**
- Navigation to `SIGNIN_URL` now resolves to a boolean; on failure the script throws
  `Failed to navigate to Pluralsight signin page` instead of silently continuing.
- Success now requires both `!page.url().includes('/signin')` **and** `_pageLooksLoggedIn(page)`
  (logged-in selector visible) — a stale URL alone can no longer produce `ACG_SESSION_OK`.
- Empty context now creates a page (`context.newPage()`) instead of throwing.

### Finding 2 — `node` executed with no preflight (cdp.sh)

Copilot: `_cdp_ensure_acg_session` runs `node` unconditionally; missing Node or the playwright
module yields a generic 127 instead of the consistent `_err` messaging used elsewhere.

**Fix (`dd564c2`):** added `_command_exist node` and `node_modules/playwright` preflight checks,
each calling `_err` with an actionable message.

### Findings 3–5 — doc accuracy (specs/bugs on the branch)

- `CHANGE.md` → `CHANGELOG.md` in `docs/plans/v0.1.8-antigravity-migration.md` (this repo uses
  `CHANGELOG.md`; the "Files Changed" table and DoD pointed at a non-existent file).
- Bare "Do NOT create a PR" reworded to the documented retro convention
  ("Do NOT create a PR yourself — Claude handles PR creation after verifying the commit") in the
  v0.1.8 spec and two bug docs.

---

## lib-foundation #31 — `scripts/lib/system.sh`, `scripts/tests/lib/system.bats`

### Finding 1 — `curl | bash` bypasses `_run_command`; no PATH/hash refresh (system.sh)

Copilot: the direct `curl … | bash` bypasses the library's consistent `_run_command` error
handling, and after install the shell command hash is not refreshed.

**Fix (`9bdf776`):** installer download routed through `_run_command -- curl … | bash` (matches the
existing convention at `system.sh:690`); `hash -r` after a successful install.

### Finding 2 — missing-`curl` error path untested (system.sh)

**Fix (`9bdf776`):** added a BATS test asserting the `_err "curl is required…"` path. Test sandboxes
`HOME` (`export HOME="${BATS_TEST_TMPDIR}"`) so the `~/.local/bin/agy` existence guard does not
short-circuit, and never touches the real `agy` binary. Suite is now 23/23 green.

### Findings 3–4 — spec references wrong test file (ensure-agy-cli.md)

Spec listed `scripts/tests/lib/ensure_agy_cli.bats`, but tests were added to the existing
`scripts/tests/lib/system.bats`. Corrected the file list, the §4 heading, and the Files-Changed table.

---

## Root cause

The migration code was first committed into the k3d-manager subtree mirrors (wrong repo) and
salvaged. During relocation the JS/spec carried over verbatim, including the `.catch(() => {})`
false-positive seam and the `CHANGE.md`/test-file references that don't match lib-acg's layout.

## Process note

When relocating salvaged code into its owning repo, re-validate it against **that repo's**
conventions (changelog filename, test harness location, `_run_command` usage) — not just that it
"runs". Copilot caught the false-positive seam that bash/node syntax checks could not.
