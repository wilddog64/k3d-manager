# Issue: Jenkins Should Be Optional

**Date:** 2026-03-17
**Status:** INCOMPLETE — ldap.sh and vault.sh gates missing

---

## Problem

Jenkins is deployed unconditionally even though CI/CD now runs on GitHub Actions and ArgoCD.
Jenkins consumes memory on the infra cluster and seeds LDAP/Vault resources that are unused.

---

## What Was Done (08dc1bd)

- `scripts/plugins/jenkins.sh` — `deploy_jenkins()` gated behind `ENABLE_JENKINS=1` ✅
- `scripts/tests/plugins/jenkins_optional.bats` — BATS coverage for unset/0 cases ✅

---

## What Is Still Missing

### 1. `scripts/plugins/ldap.sh` — jenkins LDAP seeding not gated

Even with `ENABLE_JENKINS=0`, the LDAP seeding function still:
- Fetches `jenkins-admin` password from Vault
- Appends `jenkins-admin` to `group_members`
- Creates `cn=jenkins-admins` group in LDIF
- Creates `jenkins-admin` user entry in LDIF

Wrap the jenkins-specific blocks behind `ENABLE_JENKINS`:

```bash
local enable_jenkins="${ENABLE_JENKINS:-0}"

# Gate the Vault secret fetch:
if [[ "$enable_jenkins" == "1" ]]; then
   local jenkins_secret_json=""
   jenkins_secret_json=$(_vault_exec --no-exit "$vault_ns" "vault kv get -format=json ${mount}/${JENKINS_ADMIN_VAULT_PATH:-eso/jenkins-admin}" "$vault_release" 2>/dev/null || true)
   if [[ -n "$jenkins_secret_json" ]]; then
      jenkins_password=$(printf '%s' "$jenkins_secret_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("data",{}).get("data",{}).get("password",""))' 2>/dev/null || true)
   fi
fi
```

Gate the `group_members` append and the jenkins-admins group + user LDIF blocks the same way.

### 2. `scripts/plugins/vault.sh` — `_vault_set_eso_init_jenkins_writer` not gated

In `_enable_kv2_k8s_auth()`, wrap:

```bash
if [[ "${ENABLE_JENKINS:-0}" == "1" ]]; then
   _vault_set_eso_init_jenkins_writer "$ns" "$release" "$eso_sa" "$eso_ns"
fi
```

---

## Remaining Codex Task

1. `git checkout k3d-manager-v0.9.4 && git pull origin k3d-manager-v0.9.4`
2. Apply the two missing gates above
3. `shellcheck scripts/plugins/ldap.sh scripts/plugins/vault.sh` — no new warnings
4. `bats scripts/tests/plugins/` — all pass
5. Commit on `k3d-manager-v0.9.4`, push, update this file with SHA and status → **COMPLETE**
6. Update `memory-bank/activeContext.md` and `memory-bank/progress.md`

---

## Original Spec

`docs/issues/v0.9.4-codex-jenkins-optional.md`
