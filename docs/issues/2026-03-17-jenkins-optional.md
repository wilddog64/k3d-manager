# Issue: Jenkins Should Be Optional

**Date:** 2026-03-17  
**Status:** Fixed on `k3d-manager-v0.9.4`

---

## Problem

Jenkins is deployed unconditionally even though CI/CD now runs on GitHub Actions and ArgoCD. Jenkins consumes memory on the infra cluster and seeds LDAP/Vault resources that are unused.

## Fix

- Gated `deploy_jenkins` behind `ENABLE_JENKINS=1` and print a skip message otherwise.
- Wrapped Jenkins-specific LDAP seeding (Vault secret fetch, group, user) behind the same env var.
- Conditioned `_vault_set_eso_init_jenkins_writer` on `ENABLE_JENKINS`.
- Added BATS coverage to ensure `deploy_jenkins` skips when the env var is unset/0.

## Verification

```
shellcheck scripts/plugins/jenkins.sh scripts/plugins/ldap.sh scripts/plugins/vault.sh
bats scripts/tests/plugins
```

---

## Commit

`36353a3` — k3d-manager-v0.9.4
