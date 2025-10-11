# Changelog

## v0.1.4 — 2024-10-11

- Retired the legacy `scripts/tests/lib` location in favor of `scripts/tests/system`, updated the harness (`k3d-manager test system`), and refreshed documentation to match (`scripts/lib/help/utils.sh`, `README.md`).

## v0.1.3 — 2025-10-11

- Added Jenkins live-update support with rollout-aware readiness checks, allowing `deploy_jenkins --live-update` to run Helm upgrades while waiting for the controller pod to recycle cleanly (`scripts/plugins/jenkins.sh`, `scripts/tests/plugins/jenkins.bats`).
- Hardened tracing for secret operations by streaming Vault payloads through temp files so `ENABLE_TRACE=1` no longer exposes base64-encoded credentials (`scripts/lib/system.sh`, `scripts/tests/system/sync_lastpass_ad.bats`, `docs/plans/trace-hardening.md`).
- Documented the live-update workflow and new flags in the README and supporting plan notes (`README.md`, `docs/plans/jenkins-live-update.md`).

## v0.1.2 — 2024-10-10

 - Integrated LastPass-backed Active Directory sync directly into the Jenkins deployment helper, keeping credentials off the command line and adding comprehensive BATS coverage (`scripts/lib/system.sh`, `scripts/plugins/jenkins.sh`, `scripts/tests/system/sync_lastpass_ad.bats`, `scripts/tests/plugins/jenkins.bats`).
- Restructured documentation: trimmed the root `README.md` to a quick start and command index, moved k3s and Jenkins details into dedicated guides, and documented the refactor plan (`docs/k3s-guide.md`, `docs/jenkins-deployment.md`, `docs/readme-refactor-plan.md`).
- Captured the LastPass integration intent in `docs/plans/sync-lastpass-integration.md`.

## v0.1.1 — 2024-10-10

- Reset versioning after synchronising LastPass AD credentials with Vault.
