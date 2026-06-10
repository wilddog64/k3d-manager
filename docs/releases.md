# Releases

## [0.3.0] - 2026-05-21

### Changed
- `scripts/plugins/acg.sh`: make CloudFormation template path configurable via `ACG_CLUSTER_TEMPLATE` env var (default: `${_LIB_ACG_ROOT}/scripts/etc/acg-cluster.yaml`)

### Fixed
- `scripts/etc/acg-cluster.yaml`: restore CloudFormation template deleted in v0.2.0; add security fixes (remove `AllowedCidr` default, parametrize IAM role names)
- `scripts/hooks/pre-commit`: add dangling-reference gate to prevent file-deletion bugs
- `acg_restart.js`: provider-scope button lookup; improve error handling
- `bin/acg-credential-test`: add mandatory `sts:GetCallerIdentity` validation on all exit paths
- `acg_extend.js`: fix SPA re-navigation timing; increase button visibility timeout

## [0.2.0] - 2026-05-20

### Fixed
- `acg_restart.js`: use `dispatchEvent` for React event delegation; scope confirm button to alertdialog
- `acg_restart.js`: fast-path for already-deleted sandbox; increase timeouts (Start: 120s→180s, overall: 240s)
- `bin/acg-credential-test`: refactor into `_extract_credentials` / `_sts_valid` helpers
- `acg_extend.js`: add `--check` flag for TTL inspection; provider-scoped button lookup

### Added
- `tests/fixtures/sandbox.html`: self-contained Pluralsight sandbox fixture with state machine
- `tests/acg-restart.spec.js`: 7 Playwright fixture tests covering full delete flow & role scoping
- `playwright.config.js`: `@playwright/test` configuration
- CI `e2e` job: fixture-based tests on every PR

### Removed
- `scripts/etc/acg-cluster.yaml`: CloudFormation template (moved to k3d-manager)

## [0.1.0] - 2026-05-19

### Fixed
- `acg_extend.js`: narrow midnight-wrap guard; add `--check` mode for TTL reporting
- `scripts/plugins/acg.sh`: add `acg_check_ttl()` wrapper

### Added
- Initial release: Chrome CDP bootstrap, ACG session management, Playwright scripts, provider plugins
