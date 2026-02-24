# GitGuardian False Positive: LDAP_PASSWORD_ROTATOR_IMAGE

**Date:** 2026-02-23
**Status:** False Positive — No real secret exposed
**GitGuardian Incident:** [#22639636](https://dashboard.gitguardian.com/workspace/359778/incidents/22639636)
**Flagged Commit:** `625ef0e3cc002a99a3d8b40e2e29e8396db2001f`
**Flagged File:** `scripts/etc/ldap/vars.sh`, line 99

---

## What GitGuardian Reported

GitGuardian flagged a "Generic Password" in `scripts/etc/ldap/vars.sh` at line 99:

```bash
export LDAP_PASSWORD_ROTATOR_IMAGE="${LDAP_PASSWORD_ROTATOR_IMAGE:-docker.io/bitnami/kubectl:latest}"
```

## Root Cause: False Positive

This is a false positive triggered by two heuristics in GitGuardian's generic password detector:

1. **Variable name** contains `PASSWORD` — `LDAP_PASSWORD_ROTATOR_IMAGE`
2. **Default value** `docker.io/bitnami/kubectl:latest` matches a generic credential pattern
   (colon-separated string with alphanumeric segments)

The actual value is a **Docker image reference**, not a credential. No real secret was
exposed. All actual password variables in this file use empty defaults (`${VAR:-}`) or
reference Vault paths — never hardcoded values.

## Verification

Full audit of password-related variables in `scripts/etc/ldap/vars.sh`:

| Variable | Default Value | Real Secret? |
|---|---|---|
| `LDAP_BIND_PASSWORD` | `""` (empty) | No |
| `LDAP_ADMIN_PASSWORD_KEY` | `LDAP_ADMIN_PASSWORD` (key name only) | No |
| `LDAP_CONFIG_PASSWORD_KEY` | `LDAP_CONFIG_PASSWORD` (key name only) | No |
| `LDAP_PASSWORD_ROTATOR_IMAGE` | `docker.io/bitnami/kubectl:latest` | No — Docker image |
| `LDAP_HELM_REGISTRY_PASSWORD` | `""` (empty) | No |

## Resolution

**Immediate:** Mark as false positive in the GitGuardian dashboard.

**Long-term fix:** Rename `LDAP_PASSWORD_ROTATOR_IMAGE` to `LDAP_ROTATOR_IMAGE` to remove
`PASSWORD` from the variable name and prevent future false positives. Also rename the
related variables:
- `LDAP_PASSWORD_ROTATOR_ENABLED` → `LDAP_ROTATOR_ENABLED`
- `LDAP_PASSWORD_ROTATOR_IMAGE` → `LDAP_ROTATOR_IMAGE`
- `LDAP_PASSWORD_ROTATION_SCHEDULE` → `LDAP_ROTATION_SCHEDULE`
- `LDAP_PASSWORD_ROTATION_PORT` → `LDAP_ROTATION_PORT`

**Alternative:** Add a `.gitguardian.yml` ignore rule for this variable pattern if renaming
is not desirable.

## Prevention

Add `ggshield` as a pre-commit hook to catch any real secrets before they leave the
local machine:

```bash
pip install ggshield
ggshield secret hook install
```

This is also noted in the CI workflow plan (`docs/plans/ci-workflow.md`) under the
Secret Hygiene principle.
