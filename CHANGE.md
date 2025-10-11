# Changelog

## v0.1.2 — 2024-10-10

- Integrated LastPass-backed Active Directory sync directly into the Jenkins deployment helper, keeping credentials off the command line and adding comprehensive BATS coverage (`scripts/lib/system.sh`, `scripts/plugins/jenkins.sh`, `scripts/tests/lib/sync_lastpass_ad.bats`, `scripts/tests/plugins/jenkins.bats`).
- Restructured documentation: trimmed the root `README.md` to a quick start and command index, moved k3s and Jenkins details into dedicated guides, and documented the refactor plan (`docs/k3s-guide.md`, `docs/jenkins-deployment.md`, `docs/readme-refactor-plan.md`).
- Captured the LastPass integration intent in `docs/plans/sync-lastpass-integration.md`.

## v0.1.1 — 2024-10-10

- Reset versioning after synchronising LastPass AD credentials with Vault.
