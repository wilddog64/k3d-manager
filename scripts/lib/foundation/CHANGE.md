# Changes - lib-foundation

## [v0.4.7] — 2026-07-23

Make the `acg_check_ttl` node exit-code capture `set -e`-safe — the last remaining instance of the non-set-e-safe idiom in `acg.sh` (PR #38, merged `a36cf79`). Documented PR #37 follow-up.

### Fixed
- `scripts/lib/acg/acg.sh`: `acg_check_ttl` captured the node `--check` exit code with a separate `exit_code=$?` line; under `set -euo pipefail` a non-zero node exit aborted the caller at the assignment, leaving the graceful `node exited N → return 1` path dead. Moved the capture into `output=$(node …) || exit_code=$?`, matching the sibling `_acg_extend_playwright` / `_acg_restart_playwright` wrappers. Happy path unchanged; only the failure path is now reachable (`a36cf79`).

## [v0.4.6] — 2026-07-21

Restore the `acg_restart` shell entrypoint for the orphaned `acg_restart.js` and stop the ACG browser wrappers from leaking stale `playwright-artifacts-*` temp dirs (PR #37, merged `db336a6f`). Folds in the never-released v0.4.5 `acg_restart` wiring.

### Added
- `scripts/lib/acg/acg.sh`: `acg_restart` public function + `_acg_restart_playwright` helper wire the previously orphaned `playwright/acg_restart.js` (delete dead sandbox → Start Sandbox → re-extract credentials) to a shell entrypoint, so an expired/dead ACG sandbox is recovered with zero manual clicks. `_acg_check_credentials` now points operators at `acg_restart` instead of the manual "Start a new sandbox" instructions (`03312ae`, folded-in v0.4.5).

### Fixed
- `scripts/lib/acg/acg.sh`: `_acg_sweep_stale_artifacts` removes `playwright-artifacts-*` directories older than 120 minutes from `$TMPDIR`, called from both `_acg_extend_playwright` and `_acg_restart_playwright`, so repeated ACG runs no longer leak Playwright scratch dirs into `/tmp` (`84d5b27`). Guards against an empty sweep path when `TMPDIR=/` via `${tmpdir:-/}` (Copilot PR #37 finding, `330083b`).
- `scripts/lib/acg/acg.sh`: make the node exit-code capture in `_acg_extend_playwright` and `_acg_restart_playwright` `set -e`-safe — `output=$(node …) || exit_code=$?` instead of a separate `exit_code=$?` line that aborts the caller under `set -euo pipefail` before the graceful `return 1` path is reached (Copilot PR #37 finding, `330083b`).

### CI
- `scripts/lib/acg/acg.sh`: silence SC2119/SC2120 on the intentional argless internal `acg_get_credentials` call surfaced by CI's newer shellcheck build (`1c0dc51`).

## [v0.4.4] — 2026-07-13

Close the dev-only js-yaml DoS advisory (GHSA-h67p-54hq-rp68) on the ACG test toolchain and fix ACG Extend sandbox-tab routing (PR #36, merged `ce421a4`).

### Security
- `scripts/lib/acg/package-lock.json`: bump the dev-only transitive `js-yaml` from `3.14.2` to `3.15.0` to close Dependabot advisory GHSA-h67p-54hq-rp68 (medium — quadratic-complexity DoS in merge-key handling via repeated aliases). `js-yaml` is pulled in only by the jest/babel test toolchain; `3.15.0` satisfies the existing `^3.13.1` range so `package.json` is unchanged.

### Fixed
- `scripts/lib/acg/playwright/acg_extend.js`: route the sandbox Extend flow through sandbox-page checks instead of adopting a stale Pluralsight CDP tab. The old logic picked the first `.pluralsight.com` tab and treated any Pluralsight hostname as "already on the right page," so a reused CDP tab at `s2.pluralsight.com/404.html` skipped navigation to Cloud Sandboxes and failed with "Extend button not found." Now normalizes sandbox URLs, prefers actual sandbox tabs, forces navigation when the reused tab is a non-sandbox page, and fails explicitly on sign-in redirect. Covered by a new `s2.pluralsight.com/404.html` regression test (`scripts/lib/acg/tests/providers/acg_extend.test.js`).

## [v0.4.3] — 2026-07-07

Harden the ACG session-check against a render-timing race that produced false "logged out" negatives when reusing an already-signed-in CDP browser (PR #35, merged `b7d08b3`).

### Fixed
- `scripts/lib/acg/playwright/lib/pluralsight_login.js`, `scripts/lib/acg/acg_session_check.js`: harden the ACG session-check against a render-timing race that produced false "logged out" negatives when reusing an already-signed-in CDP browser. `pageLooksLoggedIn` now retries across a short settle window (backward-compatible optional `{ attempts, perSelectorTimeoutMs, settleMs }` — no options = single-shot as before); the initial sandbox probe waits for `networkidle` then retries (`attempts: 4`), logs nav failures instead of silently swallowing them, and the post-auto-login re-check retries (`attempts: 3`). `LOGGED_IN_SELECTORS` and the credential/auto-login gating are unchanged. Covered by new render-race regression tests (`d803a00`).

### Performance
- `scripts/lib/acg/playwright/lib/pluralsight_login.js`: parallelize `anyVisible` so each logged-in probe is bounded by one per-selector timeout instead of `selectors.length × perSelectorTimeoutMs`. Resolves `true` on the first visible selector (fast happy path unchanged) and `false` only once all resolve, keeping the `{ attempts }` retry worst case from ballooning into tens of seconds on a genuinely logged-out page (`487b2f9`, Copilot PR #35 finding).

## [v0.4.2] — 2026-07-06

Headless CDP auto-login with stale-browser reclaim/reuse on the AWS-sandbox credential-test path (PR #34, merged `ae9fc73`).

### Fixed
- `scripts/lib/acg/cdp.sh`: replace the BUG #4 reuse-branch hard error with a Playwright `connectOverCDP` health probe and automatic `:9222` reclaim, so healthy managed browsers are reused and stale, zombie, or version-mismatched listeners are terminated and relaunched instead of requiring a manual `kill`.
- `scripts/lib/acg/cdp.sh`, `scripts/lib/acg/bin/acg-credential-test`: route `acg-credential-test` through `_browser_launch` so the managed browser self-launches on the credential-test path instead of adopting stale system Chrome. (An interim profile-identity hard-reject of foreign `:9222` listeners was superseded by the reuse/reclaim health probe above.)
- `scripts/lib/acg/cdp.sh`: wire `_cdp_ensure_acg_session` into `_browser_launch` on both the already-running and freshly-launched Chrome CDP paths, so headless Pluralsight login runs before AWS sandbox credential extraction instead of falling through to stale credentials and `InvalidClientTokenId`.
- `scripts/lib/acg/bin/acg-credential-test`: run the existing `_cdp_ensure_acg_session` headless Pluralsight gate on the standalone `make credential-test` path, and make `playwright/lib/browser.js` fail clearly when CDP is reachable but exposes no usable context instead of attempting `launchPersistentContext` on the locked live profile.
- `scripts/lib/acg/cdp.sh`: launch Playwright-managed Chromium for CDP instead of system Chrome, and move the dedicated profile default from `profile` to `pw-profile` so the CDP target stays version-locked to the pinned Playwright and avoids newer-system-Chrome profile incompatibility.

## [v0.4.1] — 2026-07-06

Headless Pluralsight auto-login for unattended AWS-sandbox provisioning (PR #33, merged `b7c849c`).

### Added
- `scripts/lib/acg/`: headless Pluralsight auto-login for unattended provisioning (`bbc87ec`). New `playwright/acg_pluralsight_login.js` drives the sign-in flow over CDP; `playwright/lib/pluralsight_login.js` holds the shared `loginWithPage` helper (selectors + MFA detection) reused by both the login script and `acg_session_check.js`. `cdp.sh` now loads `k3dm-acg-pluralsight` credentials via `_secret_load_data` and passes them to the node scripts as `ACG_USERNAME`/`ACG_PASSWORD` env vars (never on argv), and threads `K3DM_NONINTERACTIVE`. `acg_session_check.js` fails fast (`ACG_LOGIN_NO_CREDS` / no polling) when non-interactive with no creds or an unsolvable MFA prompt, instead of hanging. Browser handles are released with `browser.close()` (not `disconnect()`) for CDP correctness. Covered by new `tests/providers/acg_session_check.test.js` and `tests/providers/pluralsight_login.test.js` (no-creds, non-interactive fast-fail, MFA-refuse branches).

### Fixed
- `scripts/lib/acg/bin/acg-credential-test`: replace call to the undefined `_sts_valid` (exited 127 → `!` always-true → spurious sandbox restart on every happy-path AWS run) with the canonical inline `AWS_CONFIG_FILE=/dev/null aws sts get-caller-identity` probe. Pre-existing, imported verbatim from lib-acg `7708ae31`.

## [v0.4.0] — 2026-06-22

Absorbs the standalone lib-acg repo as an optional module and retires the 3-level subtree chain (PR #32, merged `aed8c56`).

### Added
- `scripts/lib/acg/`: optional ACG browser-automation module absorbed from lib-acg (source `7708ae31`, v0.1.9). Public API `acg_*` (AWS sandbox lifecycle) and `gcp_*` (GCP credential extraction); Chrome CDP primitives in `cdp.sh`; Playwright scripts under `playwright/`. Sources `../system.sh` for `_run_command` (no vendored foundation). Node deps are opt-in (`npm ci` in `scripts/lib/acg/`); sourcing core stays zero-node. Retires the lib-acg standalone repo + the 3-level subtree chain.
- acg module: import `playwright.config.js`; add a repo-root `Makefile` that `cd`s into `scripts/lib/acg` before invoking the `bin/` entry points. The `bin/` scripts stay module-local (matching the upstream lib-acg layout) so the live browser flow runs with the module as its working directory — a hoisted repo-root `bin/` regressed the Playwright sandbox-delete flow (Phase 1 follow-up).
- `scripts/lib/system.sh`: `_ensure_agy_cli` — install the standalone Antigravity agent CLI (`agy`) into `~/.local/bin` via `_run_command -- curl … | bash`; idempotent (no-op if `agy` on PATH or `~/.local/bin/agy` exists), user-scope (no sudo); refreshes the shell command hash after install. Distinct from `_ensure_antigravity_ide` (the IDE cask). Covered by 3 mocked BATS tests in `scripts/tests/lib/system.bats` (present, install, missing-curl).
- `scripts/tests/lib/agent_rigor.bats`: 2 new tests — `_agent_lint` picks up staged `.js` and `.md` files via `AGENT_LINT_AI_FUNC` mock (PR #27, #28)

### Changed
- Make `_cluster_provider` validation extensible via optional `_cluster_provider_is_extra_supported` consumer hook (PR #30)
- `docs/api/functions.md`: remove stale `export K3DM_ENABLE_AI=1` from `_copilot_review` usage example; fix `_agent_lint` pre-commit hook example to use `ENABLE_AGENT_LINT=1` instead of `K3DM_ENABLE_AI`; correct gate variable description (PR #27, #28)

### Fixed
- `scripts/lib/system.sh`: `_run_command_resolve_sudo` — fall back to `sudo -n` when no TTY is present; fixes `sudo: unable to allocate pty: Device not configured` failures when non-interactive shells call `_run_command --interactive-sudo` (e.g., `make up` from a terminal with cached sudo credentials) (PR #29)

## [v0.3.19] — 2026-05-03

Back-filled (2026-06-22): tag `v0.3.19` (`45040e2`) was cut straight off `[Unreleased]` without a section. Supersedes the never-tagged v0.3.18 (its `_copilot_auth_check` work shipped here).

### Added
- `scripts/tests/lib/copilot_auth.bats`: 6-test BATS suite covering all auth paths — env token (3 variants), `apps.json`, `gh auth status` fallback, and failure with clear error message (`f0e29d9`)

### Fixed
- `scripts/lib/system.sh`: `_copilot_review` — add `--allow-all-tools` flag and close malformed `--deny-tool` patterns (`shell(sudo`, `shell(eval`, `shell(curl`, `shell(wget` were missing closing `)`) — Copilot CLI exits 1 on malformed patterns, blocking all `_ai_agent_review` callers (`713c18e`)
- `scripts/lib/system.sh`: `_copilot_auth_check` — remove `K3DM_ENABLE_AI` gate; check env tokens (`COPILOT_GITHUB_TOKEN`/`GH_TOKEN`/`GITHUB_TOKEN`), then `~/.config/github-copilot/apps.json`, then `gh auth status`; `_err` on failure with clear message — Copilot v1.0.40 has no `auth status` subcommand (`f0e29d9`, `eede5c3`)

## [v0.3.17] — 2026-05-01

### Added
- `scripts/lib/system.sh`: `_ai_agent_review` — generic AI dispatch wrapper; routes to backend selected by `AI_REVIEW_FUNC` (default: `copilot`) with model from `AI_REVIEW_MODEL` (default: `gpt-5.4-mini`); passes all args through to the selected backend (`448560a`)
- `scripts/tests/lib/ai_agent_review.bats`: 3-test BATS suite — default dispatch to `_copilot_review`, `AI_REVIEW_MODEL` override, unknown `AI_REVIEW_FUNC` error path (`448560a`)
- `docs/api/functions.md`: `_ai_agent_review` function entry + `AI_REVIEW_FUNC` / `AI_REVIEW_MODEL` env var table in Copilot CLI Integration section (`448560a`)

### Changed
- `scripts/lib/system.sh`: `_k3d_manager_copilot` renamed to `_copilot_review` — aligns with the `_copilot_*` helper family; no behavior change (`d24b457`)
- `docs/api/functions.md`: Copilot CLI Integration section — full documentation of `_copilot_auth_check`, `_copilot_scope_prompt`, `_copilot_prompt_guard`, `_copilot_review` with usage examples and adoption pattern (`98a58e0`)

### Fixed
- `scripts/lib/system.sh`: removed `K3DM_ENABLE_AI` gate from `_copilot_review` — a lib-foundation backend must not check a consumer-specific env var; gate belongs in callers (`657fd91`)
- `scripts/lib/agent_rigor.sh`: `_agent_lint` staged-files glob expanded to `.sh`, `.js`, `.md` — previously only matched `.sh` (`af1356a`)

## [v0.3.16] — 2026-04-05

### Fixed
- `_agent_audit` IP allowlist: use `grep -Fqx -- "$file"` to prevent repo-relative paths beginning with `-` from being parsed as grep flags.

## [v0.3.15] — 2026-03-31

### Fixed
- `_agent_audit` IP audit loop — supports `AGENT_IP_ALLOWLIST` env var; when set to a readable regular file, skips IP literal check for paths listed in it (one repo-relative path per line; lines beginning with `#` are ignored). Consumers set this env var before running `_agent_audit` (for example, in the pre-commit hook environment).

## [v0.3.14] — 2026-03-27

### Fixed
- `_ensure_antigravity_ide()` — detect `agy` (Homebrew macOS binary) alongside `antigravity` at all 4 detection points
- `_antigravity_browser_ready()` — fail fast with clear error when `curl` missing, instead of silently looping to timeout
- `_agent_audit` tab-indentation scan — replace word-splitting `for file in $changed_sh` with NUL-delimited `while IFS= read -r -d ''` loop; safe for filenames with spaces
- `docs/api/functions.md` — document `PLAYWRIGHT_MCP_VERSION` pinned default; remove `@latest` inaccuracy
- `CHANGE.md` — version shipped v0.3.12 and v0.3.13 entries (were `[Unreleased]`)

## [v0.3.13] — 2026-03-25

### Fixed
- `_antigravity_browser_ready()` — replace `_curl` boolean probe with `_run_command --soft -- curl` so the poll loop retries instead of calling `exit 1` on the first failed attempt

## [v0.3.12] — 2026-03-25

### Added
- `_ensure_antigravity_ide()` — install Antigravity IDE via brew (macOS), apt-get (Debian), or dnf (RedHat)
- `_ensure_antigravity_mcp_playwright()` — inject Playwright MCP entry into Antigravity `mcp_config.json` (requires `jq`; idempotent)
- `_antigravity_browser_ready()` — verify Antigravity remote debugging port 9222 is listening; configurable timeout
- `_antigravity_mcp_config_path()` — resolve Antigravity `mcp_config.json` path for macOS/Linux

## [v0.3.11] — 2026-03-25

### Added
- `scripts/lib/agent_rigor.sh`: YAML hardcoded-IP check in `_agent_audit` — staged `.yaml`/`.yml` files containing IPv4 addresses now fail the pre-commit hook; warns to use CoreDNS hostname instead.
- `scripts/tests/lib/agent_rigor.bats`: two new tests covering clean YAML (pass) and hardcoded-IP YAML (fail) scenarios.

---

## [v0.3.10]

### Fixed
- `.clinerules`: correct `_detect_platform` return values — `mac | wsl | debian | redhat | linux` (was `debian | rhel | arch | darwin | unknown`)

---

## [v0.3.8] — _agent_audit tab indentation enforcement

### Added
- `scripts/lib/agent_rigor.sh`: tab indentation check in `_agent_audit` — staged `.sh` files containing tab-indented lines now fail the pre-commit hook; enforces 2-space style across all shell scripts.
- `scripts/tests/lib/agent_rigor.bats`: two new tests covering tab-indented (fail) and 2-space-indented (pass) scenarios.

### Fixed
- `scripts/tests/lib/system.bats`: assert exit status in quiet-mode `_run_command_handle_failure` test.

---

## [v0.3.7] — system.sh if-count cleanup

### Changed
- `scripts/lib/system.sh`: extracted `_run_command_handle_failure` and `_node_install_via_redhat` helpers so `_run_command`/`_ensure_node` drop to ≤8 ifs; clears remaining allowlist entries.
- `scripts/tests/lib/system.bats`: added coverage for `_run_command_handle_failure` soft/quiet modes and `_node_install_via_redhat` fallback behavior.
