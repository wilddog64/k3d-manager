# Issue: Jenkins Should Be Optional

**Date:** 2026-03-17
**Status:** COMPLETE — Jenkins fully gated via ENABLE_JENKINS

---

## Problem

Jenkins is deployed unconditionally even though CI/CD now runs on GitHub Actions and ArgoCD.
Jenkins consumes memory on the infra cluster and seeds LDAP/Vault resources that are unused.

---

## Fix Summary

- `scripts/plugins/jenkins.sh` — `deploy_jenkins()` exits early unless `ENABLE_JENKINS=1` (`08dc1bd`).
- `scripts/plugins/ldap.sh` — Jenkins Vault secret fetch + LDIF entries now gated behind `ENABLE_JENKINS` (`4b02e16`).
- `scripts/plugins/vault.sh` — `_vault_set_eso_init_jenkins_writer` only runs when Jenkins is enabled (`4b02e16`).
- `scripts/tests/plugins/jenkins_optional.bats` — BATS coverage for unset/0 cases (`08dc1bd`).

## Verification

```
shellcheck scripts/plugins/jenkins.sh scripts/plugins/ldap.sh scripts/plugins/vault.sh
env -i PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin" HOME="$HOME" TMPDIR="$TMPDIR"   bash --norc --noprofile -c 'bats scripts/tests/plugins/jenkins_optional.bats'
```

## Commits

- `08dc1bd` — adds gate + tests
- `4b02e16` — gates LDAP/Vault resources

---
## Fix Summary

- `scripts/plugins/jenkins.sh` — `deploy_jenkins()` exits early unless `ENABLE_JENKINS=1` (`08dc1bd`).
- `scripts/plugins/ldap.sh` — Jenkins Vault secret fetch + LDIF entries now gated behind `ENABLE_JENKINS` (`4b02e16`).
- `scripts/plugins/vault.sh` — `_vault_set_eso_init_jenkins_writer` only runs when Jenkins is enabled (`4b02e16`).
- `scripts/tests/plugins/jenkins_optional.bats` — BATS coverage for unset/0 cases (`08dc1bd`).

## Verification

```
shellcheck scripts/plugins/jenkins.sh scripts/plugins/ldap.sh scripts/plugins/vault.sh
env -i PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin" HOME="$HOME" TMPDIR="$TMPDIR"  bash --norc --noprofile -c 'bats scripts/tests/plugins/jenkins_optional.bats'
```

## Commits

- `08dc1bd` — adds gate + tests
- `4b02e16` — gates LDAP/Vault resources
