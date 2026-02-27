# Issue: test_vault fails — ClusterRoleBinding conflict when Vault already deployed

**Date:** 2026-02-26
**Status:** OPEN
**Severity:** Blocks Stage 2 CI validation on m2-air

---

## Symptom

Running `./scripts/k3d-manager test_vault` against a cluster with Vault already deployed
fails immediately:

```
Error: unable to continue with install: ClusterRoleBinding "vault-server-binding" in
namespace "" exists and cannot be imported into the current release: invalid ownership
metadata; annotation validation error: key "meta.helm.sh/release-namespace" must equal
"vault-test-1772113808-27191": current value is "vault"
```

Cleanup then deletes `vault-server-binding`, corrupting the live Vault deployment.

---

## Root Cause

`test_vault` in `scripts/lib/test.sh` (line 681) calls:

```bash
"${SCRIPT_DIR}/k3d-manager" deploy_vault "$test_ns" "$vault_release"
```

where `$test_ns` is a random namespace (e.g. `vault-test-1772113808-27191`).

This attempts to install a **second** Vault Helm release into the random namespace.
`vault-server-binding` is a cluster-scoped ClusterRoleBinding — it has no namespace.
It was created by the existing `vault` release in the `vault` namespace. Helm cannot
adopt it into a release with a different namespace annotation.

**Design mismatch:** `test_vault` was written to deploy Vault itself, but the CI model
(pre-built cluster fixture) requires testing against the already-deployed Vault instance.
The test should never deploy Vault — it should validate the running instance.

---

## Impact

- `test_vault` cannot run on any cluster where Vault is already deployed
- Cleanup trap deletes `vault-server-binding`, breaking the live Vault deployment
- Blocks Stage 2 CI validation entirely

---

## Required Fix

Refactor `test_vault` to test against the existing Vault deployment:

1. Remove the `deploy_vault "$test_ns" "$vault_release"` call entirely
2. Use the hardcoded `vault` namespace and existing release (same pattern as `test_eso`)
3. Test only Vault functionality — K8s auth, secret read — not deployment
4. Cleanup should only remove test-specific resources (test namespace, Vault role,
   seeded secret), never touch the Vault release itself

Reference: `test_eso` (line 556) already follows the correct pattern — it checks if
Vault is running and uses the existing instance rather than deploying a new one.

---

## Workaround

None — `test_vault` cannot be run on a cluster with an existing Vault deployment until
fixed.
