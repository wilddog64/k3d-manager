# Changes - lib-foundation

## [Unreleased]

### Changed
- `scripts/lib/acg/package.json`, `scripts/lib/acg/package-lock.json`: rename the package
  identity `lib-acg` → `lib-foundation-acg`. The name was inherited verbatim by the v0.4.0
  absorption tree-copy and still claimed the standalone `wilddog64/lib-acg` repo, archived
  2026-09-12. Metadata only: the package is `"private": true`, has never been published, and
  nothing resolves it by name. `version` unchanged at `0.4.0`, no dependency graph change.
  The ~89 historical `lib-acg` references in `CHANGE.md`, `docs/plans/`, `docs/bugs/`,
  `docs/issues/`, `README.md` and `docs/api/acg.md` are provenance and deliberately left
  as-is. Spec: `docs/bugs/2026-09-12-acg-package-name-still-lib-acg.md`.

### Security
- `scripts/lib/acg/package-lock.json`: bump `brace-expansion` 1.1.16 → 1.1.18
  (GHSA-mh99-v99m-4gvg, GHSA-rgw5-rvv9-x895) and `js-yaml` 3.15.1 → 3.15.2
  (GHSA-2883-xcg3-v3hh), clearing both high-severity `npm audit` findings. Both are dev-only
  transitive dependencies of `jest@29.7.0` and are not reachable from any runtime path; the
  patched releases already satisfy the semver ranges jest requests, so this is a lockfile
  refresh only — no `overrides`, no `package.json` change, no jest bump. Spec:
  `docs/bugs/2026-09-12-acg-npm-audit-brace-expansion-js-yaml.md`.

## [v0.4.17] — 2026-09-12

### Fixed
- `scripts/lib/acg/playwright/lib/pluralsight_login.js`: add
  `.psPrismAvatar .psPrismMonogram[aria-label]` to `LOGGED_IN_SELECTORS`. The current
  Pluralsight UI renders the signed-in identity as a Prism monogram, which none of the
  existing user-menu / account-label / avatar-image selectors match, so the only
  identity-based signal was missing and `pageLooksLoggedIn` fell back entirely on the
  sandbox-page text selectors (`Cloud Sandboxes` / `Open Sandbox`). Carried forward from
  the retired `wilddog64/lib-acg` PR #47; see
  `docs/bugs/2026-09-12-acg-logged-in-selectors-missing-prism-monogram.md`. The second half
  of that legacy change (an unconditional `pageLooksLoggedIn` probe before navigating) is
  deliberately NOT ported — `acg_session_check.js` here already handles navigation failure
  via `navigatedToSandbox` and retries.
- `scripts/lib/acg/playwright/lib/pluralsight_login.js`, `scripts/lib/acg/acg_session_check.js`:
  make signed-out detection explicit instead of inferring it from the absence of positive
  signals. Adds `SIGNED_OUT_SELECTORS` plus `pageLooksSignedOut` / `urlLooksSignedOut`, so
  `pageLooksLoggedIn` short-circuits to false on a recognizably signed-out page without
  burning its remaining retry attempts. Measured against a throwaway signed-out profile: a
  signed-out `SANDBOX_URL` redirects to `https://app.pluralsight.com/id`, where all three
  signed-out selectors match. The page-content markers `text=/Cloud Sandboxes/i` and
  `text=/Open Sandbox/i` are dropped from `LOGGED_IN_SELECTORS` as hygiene — they describe
  page content, not identity — leaving the Prism monogram as the identity signal.
  `acg_session_check.js` now warns explicitly when the `k3dm-acg-pluralsight` Keychain item
  is absent instead of silently skipping unattended login. See
  `docs/bugs/2026-09-12-acg-session-check-false-green-on-signed-out-page.md`, including its
  CORRECTION section: this change does **not** fix the 2026-09-12 `credential-test` failure,
  whose real cause is tracked in
  `docs/bugs/2026-09-12-acg-signin-wait-targets-dead-id-pluralsight-host.md`.
- `scripts/lib/acg/vars.sh`, `scripts/lib/acg/acg.sh`, `scripts/lib/acg/cdp.sh`: make the
  `com.k3d-manager.chrome-cdp` launchd agent actually usable. It is the mechanism that keeps
  a long-lived CDP browser — and therefore the Pluralsight session — alive between runs,
  which matters because the auth cookie `Identity.Session` is non-persistent and dies with
  the browser process. It had two defects that made it worse than useless: the plist
  hardcoded `/Applications/Google Chrome.app` (the operator's personal Chrome, superseded by
  the Playwright-managed Chromium that `cdp.sh` resolves), and `PLAYWRIGHT_AUTH_DIR` pointed
  at `~/.local/share/k3d-manager/profile` while the automation actually runs against
  `pw-profile` — measured at 0 vs 34 Pluralsight cookies. With `KeepAlive` set, loading it
  would have respawned a signed-out personal Chrome onto port 9222 after every reclaim.
  `PLAYWRIGHT_AUTH_DIR` now names `pw-profile`; browser resolution is extracted into a
  single shared `_acg_resolve_cdp_browser_bin` used by both `_browser_launch` and the plist
  writer; and the writer now fails without emitting a plist when the browser cannot be
  resolved. Neither profile directory is deleted or migrated. See
  `docs/bugs/2026-09-12-chrome-cdp-launchd-agent-wrong-browser-and-dead-profile.md`.
  Installing the agent remains a manual operator step.
- `scripts/lib/acg/bin/acg-credential-test`: stop treating an unusable CLI as invalid
  credentials, and stop destroying a working sandbox because of it. The STS probe ran as
  `aws sts get-caller-identity >/dev/null 2>&1` and keyed only on exit status, so "the aws
  binary cannot start" was indistinguishable from "STS rejected these credentials" — and
  only the latter justifies the delete-and-restart it triggered. Observed live on
  2026-09-12: a Homebrew ABI mismatch (`awscli` 2.36.44 linking `libaws-c-s3.1.0.dylib`
  against an installed `aws-c-s3` 1.1.0) made the CLI unable to start, so the tool deleted a
  live ACG sandbox and exited 1 — while the credentials it had extracted were valid,
  confirmed by a direct SigV4 call to `sts.amazonaws.com`. The restart was also futile by
  construction, since a CLI that cannot start will not start after a restart either.
  Now: `aws --version` is preflighted and an unusable CLI exits without restarting; the
  probe's stderr is retained and surfaced instead of discarded; and a restart happens only
  for recognized rejection codes (`InvalidClientTokenId`, `ExpiredToken`, `AuthFailure`,
  `SignatureDoesNotMatch`, `AccessDenied`, `UnrecognizedClientException`) — any other
  failure, including a network error, reports and exits without destroying anything. The
  same preflight guards all three Azure validation paths. See
  `docs/bugs/2026-09-12-acg-sts-probe-conflates-broken-cli-with-invalid-credentials.md`.
- `scripts/lib/acg/playwright/lib/sandbox.js`: stop waiting 300 seconds on a hostname that
  no longer exists. `handleSignIn` waited for `**id.pluralsight.com**`, but that host does
  not resolve in DNS (`dig` returns nothing; `curl` reports "Could not resolve host") —
  Pluralsight moved identity to a path on the main host, `https://app.pluralsight.com/id`.
  The glob could never match, so every sign-in recovery burned its full 300000ms timeout,
  twice per run (extraction, then the sandbox-restart path). The wait now uses a predicate
  built on `urlLooksSignedOut` with a 60s timeout, the sign-in link locator drops the dead
  host, and the post-login wait additionally requires having LEFT the identity path — it
  previously matched `app.pluralsight.com/id` itself and so could return while still
  unauthenticated. This is the actual cause of the failed 2026-09-12
  `make credential-test PROVIDER=aws` gate. See
  `docs/bugs/2026-09-12-acg-signin-wait-targets-dead-id-pluralsight-host.md`.

### Security
- `scripts/lib/acg/playwright/providers/gcp.js`: stop logging the first 30 characters of the
  captured GCP sandbox username — log `[set]`/`[empty]` presence only, matching the
  convention already used for `password` and by the debug loop at line 17. Originally raised
  as a k3d-manager Copilot finding (PR #91, 2026-06-05) and deferred there as "lib-acg
  upstream debt"; that routing died with the lib-acg archive, so the fix lands here.

## [v0.4.16] — 2026-09-12

### Security
- `scripts/lib/acg/package-lock.json`: bump the dev-only transitive `browserslist` family
  — `browserslist` 4.28.2 → 4.28.9, plus its pinned companions `baseline-browser-mapping`
  2.10.34 → 2.11.22, `caniuse-lite` 1.0.30001793 → 1.0.30001810, `electron-to-chromium`
  1.5.368 → 1.5.427, `node-releases` 2.0.47 → 2.0.55 and `update-browserslist-db`
  1.2.3 → 1.3.3 — to clear two high-severity advisories: GHSA-73wf-gq98-2v4g (uncaught
  crash / prototype write via untrusted `browserslist-stats.json` custom stats in
  `normalizeStats`, patched in 4.28.7) and GHSA-c83g-rgw3-j3cx (unbounded memory growth
  from a query cache with no eviction, patched in 4.28.7). `browserslist` is pulled in
  only by the jest/babel test toolchain at `^4.24.0`, so `package.json` is unchanged and
  the dependency shape is identical — lockfile-only, regenerated with
  `npm update --package-lock-only browserslist`; `npm ci --dry-run` resolves and
  `npm audit` no longer reports either advisory. Neither advisory is reachable in this
  module: nothing here writes or reads a `browserslist-stats.json`, and the cache growth
  needs a long-lived process issuing distinct queries. Surfaces as Dependabot alerts #9
  and #8 on the k3d-manager consumer that vendors this lockfile via subtree; that
  consumer's own PR must NOT be merged, since it would write inside the
  `scripts/lib/foundation/` subtree and be reverted by the next subtree pull. Reaches
  k3d-manager via the next lib-foundation release + subtree pull.

## [v0.4.15] — 2026-09-05

### Added
- `_install_hermes_agent [repo_root]` / `_uninstall_hermes_agent` (`scripts/lib/system.sh`): install
  and remove the off-hub Hermes read-only monitoring agent as a macOS launchd LaunchAgent (same tier
  as `bin/k3dm-webhook`, never in-cluster). Read-only by construction — the installer preflights that
  the three consumer-side read-only credentials plus the Slack relay already exist in the login
  Keychain (`security find-generic-password`, no `-w`, no secret read into the process) and **refuses
  to run if any is missing; it never mints, writes, or deletes a credential** and stands up no
  privilege at install time. Renders the consumer's `com.k3d-manager.hermes.plist.tmpl` and
  `bootout`/`bootstrap`s the agent via `_run_command`; `_is_mac` guards non-macOS hosts. Uninstall
  boots out the agent and removes the rendered plist only, leaving the user-minted Keychain
  credentials intact.

### Tests / tooling
- `scripts/tests/lib/hermes_install.bats`: five stubbed-`security`/`launchctl`/`uname` cases —
  happy-path render + `bootout`-then-`bootstrap`, missing-credential preflight installing nothing,
  non-macOS refusal, absent-template failure, and uninstall boot-out + plist removal.

## [v0.4.13] — 2026-08-21

### Added
- `foundation_ensure_vcluster_cli <version>` (`scripts/lib/system.sh`): the single owner of the
  vCluster CLI dependency for all consumers. Validates a `major.minor.patch` version (no `v`
  prefix), resolves the Loft release asset from `uname -s`/`uname -m` (`darwin`/`linux` ×
  `arm64`/`amd64`), verifies the release SHA-256 against `checksums.txt` before activation, installs
  atomically under `${XDG_DATA_HOME:-$HOME/.local/share}/lib-foundation/vcluster/<version>/vcluster`
  behind a per-version lock, reuses an already-verified binary offline, and prints only the absolute
  executable path on stdout. No package manager, no system-directory writes, and no fallback to an
  arbitrary `vcluster` on `PATH` (`b2adb8f`).

### Tests / tooling
- `scripts/tests/lib/system.bats`: seven stubbed-`curl`/`uname`/`vcluster` cases — offline reuse
  without download, verified replacement of a version mismatch, malformed/unsupported inputs writing
  nothing, checksum mismatch never activating, failed download preserving a prior binary, concurrent
  callers leaving one binary and no stale lock, and no package-manager invocation.

### Fixed
- Release the per-version lock and temp state when `mktemp` fails after the lock is acquired: the
  bare `_err` ran past a `RETURN` trap (which does not fire on `exit`), leaking the lockdir; routed
  through `_foundation_vcluster_abort` like every other post-lock failure (`f154dbe`).

## [v0.4.12] — 2026-08-21

### Added
- Count-agnostic ACG CloudFormation agent fleet. `ACG_AGENT_COUNT` (default `2`) now generates the
  deployed template: `_acg_render_template` emits `Server` + `Agent{i}Instance` / `Agent{i}PublicIP`
  for `i in 1..N` by cloning the reference agent block verbatim, so every per-agent property (instance
  profile, security group, block-device mapping, tags) is preserved by construction. Non-numeric or
  `< 1` counts fail before any `aws` call; the checked-in two-agent template stays the documented
  reference (`8148e33`).
- `_acg_discover_agent_ips`: dynamic, count-agnostic agent-IP discovery over every `Agent*PublicIP`
  stack output, ordered **numerically** (so `Agent10` follows `Agent2`, not `Agent1`) — replaces the
  hardcoded `Agent1`/`Agent2` reads.

### Tests / tooling
- `scripts/tests/lib/acg.bats`: fleet generation, default-2 preservation, numeric ordering (incl.
  `Agent10`), pre-`aws` validation of malformed/zero counts, and a no-hardcoded-`Agent1/2` guard.
- `Makefile`: `make shellcheck-lib` (all `scripts/lib/*.sh`, default severity) and `make bats`
  (scrubbed-env `scripts/tests/lib/`) local-parity targets mirroring CI; both wired into `make all`.

### Fixed
- Copilot review hardening (`32ce9c9`): render the deployed template with the portable
  `mktemp -t acg-cluster.XXXXXX` form (plus `|| return 1`) — the prior mid-string `XXXXXX.yaml`
  template broke on BSD/macOS `mktemp`; `acg_provision --help` now documents the variable
  `ACG_AGENT_COUNT` fleet and `ubuntu-<i>` agent hosts instead of a fixed 3-node cluster; the
  no-hardcoded-agent guard regex is tightened to `Agent[12]([^0-9]|$)` so it no longer false-matches
  `Agent10`/`Agent12`.

## [v0.4.11] — 2026-08-20

### Security
- Bump `js-yaml` `3.15.0` → `3.15.1` in the ACG lockfile to clear CVE-2026-59870 /
  GHSA-5p4m-2wfm-xmqj (quadratic CPU consumption in `!!omap` resolution). Dev-only transitive
  dependency (`jest` → `@istanbuljs/load-nyc-config` → `js-yaml`); the patched `3.15.1` satisfies the
  existing `^3.13.1` constraint, so the fix is a lockfile-only bump with `package.json` untouched.
  Surfaces as Dependabot alert #6 on the k3d-manager consumer that vendors this lockfile via subtree
  (`166df37`). See `docs/issues/2026-08-20-js-yaml-omap-cpu-dos-devdep.md`.

## [v0.4.10] — 2026-08-20

ACG sandbox and CDP-pipeline reliability hardening — recover credential navigation when the
sandbox lands on a stale route, and stop a single CDP probe failure from wedging the browser-launch
recovery path. Closes the "ACG login never works" / "unstable ACG pipeline" class of live failures.

### Fixed
- `scripts/lib/acg/playwright/lib/sandbox.js`: recover credential navigation when the sandbox opens
  on a stale route instead of the expected cloud-sandbox page — the navigation is re-driven to the
  correct route rather than scraping stale credentials from the wrong tab (`0a2c4cc`).
- `scripts/lib/acg/cdp.sh`: reclaim the CDP port listener when the connectivity probe fails, so a
  dead/undriveable listener is torn down and the managed Chromium is relaunched instead of the launch
  path hanging on an unusable port (`f6bb7bb`).
- `scripts/lib/acg/cdp.sh`: preserve the CDP recovery path after a probe failure — a failed probe no
  longer short-circuits the reclaim-and-relaunch sequence (`c7f7b37`).

### Tests
- `scripts/tests/lib/acg_cdp.bats`: cover listener reclaim on probe failure and isolate the
  browser-launch tests behind a per-test `HOME=$BATS_TEST_TMPDIR` + explicit listener-probe mocks, so
  the suite no longer inspects live port 9222 or writes the operator's protected Chrome log/profile
  (`f6bb7bb`, `bcd0f62`).
- `scripts/lib/acg/tests/providers/sandbox.test.js`: Jest coverage for the stale-route credential
  navigation recovery (`0a2c4cc`).

## [v0.4.9] — 2026-08-14

DRY_RUN guard primitives — Phase 0 of the foundation-first DRY_RUN project. Ships the
predicate + wrapper into the shared library so downstream consumers (k3d-manager `make
up`/`make down`) can guard mutating operations without each re-implementing the check
(PR #40, merged `1327c86`).

### Added
- `scripts/lib/system.sh`: `_dry_run_active` — predicate that is true only when
  `DRY_RUN=1` (any other value, including unset, is false). `_dry_guard "<desc>" cmd…` —
  wrapper that, in DRY_RUN, logs `INFO: DRY_RUN: would <desc>` and returns 0 without
  executing; otherwise runs the command unchanged. Guards mutating operations only —
  read-only probes stay unguarded so status/inspection paths keep working under DRY_RUN.

## [v0.4.8] — 2026-07-25

Bump `brace-expansion` to 1.1.16 to clear the high-severity DoS advisory GHSA-3jxr-9vmj-r5cp (resolves Dependabot alert #3 on the k3d-manager consumer).

### Security
- `scripts/lib/acg/package-lock.json`: bump transitive dev dependency `brace-expansion` 1.1.15 → 1.1.16 (GHSA-3jxr-9vmj-r5cp — DoS via exponential-time expansion of consecutive non-expanding `{}` groups; patched in 1.1.16). Leaf patch bump — dependency shape unchanged (`concat-map`/`balanced-match`), integrity hash matches the npm registry. Reaches the k3d-manager consumer via the next lib-foundation release + subtree pull.

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
